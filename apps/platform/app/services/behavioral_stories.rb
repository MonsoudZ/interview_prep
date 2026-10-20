class BehavioralStories
  def self.uuid!(value)
    raise Workspace::Invalid, "Invalid request identity" unless value.is_a?(String) && value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
  end
  def self.attributes!(input)
    input = input.to_unsafe_h if input.is_a?(ActionController::Parameters)
    raise Workspace::Invalid, "Expected a story" unless input.is_a?(Hash) && input.keys.sort == %w[readiness sections title topics]
    title, topics, sections, readiness = input.values_at("title", "topics", "sections", "readiness")
    unless title.is_a?(String) && title.strip.length.between?(1, 120) && topics.is_a?(Array) && topics.length.between?(1, 5) && topics.uniq == topics && (topics - BehavioralContent::TOPICS).empty? &&
        sections.is_a?(Hash) && sections.keys.sort == BehavioralContent::SECTIONS.sort && sections.values.all? { |text| text.is_a?(String) && text.valid_encoding? && text.length <= 6000 } && %w[draft ready].include?(readiness)
      raise Workspace::Invalid, "Use a title, 1–5 published topics and text sections of at most 6,000 characters each"
    end
    raise Workspace::Invalid, "Story exceeds 32 KiB" if JSON.generate(input).bytesize > 32768
    if readiness == "ready" && (BehavioralContent::SECTIONS - ["short_version"]).any? { |key| sections.fetch(key).strip.empty? }
      raise Workspace::Invalid, "Fill in the five story sections before marking it ready to rehearse"
    end
    { title: title.strip, topics: topics, sections: sections, readiness: readiness }
  end
  def self.create!(account, request_id, input)
    uuid!(request_id)
    attributes = attributes!(input)
    account.with_lock do
      existing = BehavioralStory.find_by(account: account, client_request_id: request_id)
      return existing if existing
      raise SessionCommandError.new("The story bank holds up to 100 examples, including archived stories.", status: :too_many_requests) if BehavioralStory.where(account: account).count >= 100
      BehavioralStory.create!(account: account, client_request_id: request_id, **attributes)
    end
  end
  def self.update!(story, params)
    story.with_lock do
      raise SessionCommandError, "This story changed in another tab. Your local text is kept; reload before retrying." unless params[:expected_version].is_a?(Integer) && params[:expected_version] == story.lock_version
      case params[:command]
      when "save"
        raise SessionCommandError, "Restore this story before editing it" if story.archived_at
        story.update!(attributes!(params[:story]))
      when "archive"
        story.update!(archived_at: story.archived_at || Time.current)
      when "restore"
        story.update!(archived_at: nil)
      else
        raise Workspace::Invalid, "Unknown story command"
      end
    end
    story
  end
  def self.rehearse!(account, story, exercise_id, request_id, expected_version)
    raise ActiveRecord::RecordNotFound unless story.account_id == account.id
    uuid!(request_id)
    account.with_lock do
      existing = account.interview_sessions.find_by(behavioral_request_id: request_id)
      if existing
        unless existing.behavioral_context&.fetch("story_id") == story.id && existing.exercise_version_id == exercise_id
          raise SessionCommandError, "This rehearsal request belongs to different work"
        end
        return existing
      end
      story.with_lock do
        raise SessionCommandError, "Restore this story before rehearsing it" if story.archived_at
        raise SessionCommandError, "Save and confirm the latest story before rehearsing" unless expected_version.is_a?(Integer) && expected_version == story.lock_version
        exercise = ExerciseVersion.find(exercise_id)
        raise Workspace::Invalid, "Choose a behavioral question" unless BehavioralContent.find(exercise)
        account.interview_sessions.where(status: "active").where("deadline_at <= ?", Time.current).find_each(&:expire!)
        if account.interview_sessions.where(status: %w[draft preparing ready active]).count >= 10
          raise SessionCommandError.new("Resume an existing session first (limit ten).", status: :too_many_requests)
        end
        record = account.interview_sessions.create!(exercise_version: exercise, mode: "guided", behavioral_context: BehavioralContent.context(story), behavioral_request_id: request_id)
        Workspace.save!(record, exercise.starter_files.merge("preparation.md" => BehavioralContent.story_markdown(story)))
        record
      end
    end
  end
  def self.present(story)
    { id: story.id, title: story.title, topics: story.topics, sections: story.sections, readiness: story.readiness,
      version: story.lock_version, archived_at: story.archived_at, updated_at: story.updated_at }
  end
end
