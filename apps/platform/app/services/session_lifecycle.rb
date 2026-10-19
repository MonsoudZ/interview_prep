class SessionLifecycle
  def initialize(session)
    @session = session
  end

  def start
    @session.with_lock do
      unless %w[draft ready].include?(@session.status)
        raise SessionCommandError, "Session has already started"
      end
      if @session.mode == "assessment" && @session.exercise_version.operation.present?
        unless @session.status == "ready"
          raise SessionCommandError, "Prepare the environment successfully before starting the assessment"
        end
        unless WorkerNode.available?(@session.exercise_version.operation)
          raise SessionCommandError, "Wait for a connected worker before starting the assessment"
        end
      end
      @session.update!(status: "active", started_at: Time.current,
        deadline_at: @session.mode == "assessment" ? @session.exercise_version.duration_minutes.minutes.from_now : nil)
    end
    @session
  end

  def submit(expected_revision:)
    @session.expire!
    @session.with_lock do
      @session.expire_locked!
      unless @session.status == "submitted"
        raise SessionCommandError, "Start the session before submitting" unless @session.status == "active"
        unless expected_revision == @session.current_revision
          raise SessionCommandError, "Save and confirm the latest revision before submitting"
        end
        @session.update!(status: "submitted", submitted_revision: @session.current_revision, submitted_at: Time.current)
      end
    end
    @session
  end
end
