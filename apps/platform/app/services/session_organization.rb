# Archiving changes visibility only: submissions, review evidence and progress survive.
class SessionOrganization
  def self.archive_session!(session, restore: false)
    session.expire!
    session.with_lock do
      if session.mock_interview_stage
        raise SessionCommandError, "Archive or restore the complete mock interview from Mock interviews"
      end
      raise SessionCommandError, "Submit the session before archiving it" unless session.status == "submitted"
      unless restore
        FollowupWorkflow.expire_scope!(session.followup_rounds)
        if session.followup_rounds.where(status: %w[ready active]).exists?
          raise SessionCommandError, "Finish this session's follow-up round before archiving it"
        end
      end
      session.update!(archived_at: restore ? nil : session.archived_at || Time.current)
    end
    session
  end

  def self.archive_interview!(mock, restore: false)
    MockInterviewWorkflow.sync!(mock)
    mock.with_lock do
      raise SessionCommandError, "Finish the interview before archiving it" unless mock.status == "completed"
      sessions = InterviewSession.where(id: mock.mock_interview_stages.pluck(:interview_session_id).compact)
      unless restore
        rounds = FollowupRound.where(interview_session_id: sessions.select(:id))
        FollowupWorkflow.expire_scope!(rounds)
        raise SessionCommandError, "Finish the interview's follow-up rounds before archiving it" if rounds.where(status: %w[ready active]).exists?
      end
      archived_at = restore ? nil : mock.archived_at || Time.current
      sessions.order(:id).each { |session| session.with_lock { session.update!(archived_at: archived_at) } }
      mock.update!(archived_at: archived_at)
    end
    mock
  end
end
