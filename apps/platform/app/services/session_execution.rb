# Owns execution admission and lock order; HTTP rendering stays in the controller.
class SessionExecution
  def initialize(account:, session:)
    @account = account
    @session = session
  end

  def prepare(request_id:)
    @session.expire!
    unless %w[draft preparing ready].include?(@session.status)
      raise SessionCommandError, "Preparation is available before starting"
    end
    enqueue("prepare", request_id)
  end

  def execute(request_id:)
    @session.expire!
    if @session.mock_interview_stage && !%w[active submitted].include?(@session.status)
      raise SessionCommandError, "Start this interview stage before running tests"
    end
    enqueue("tests", request_id)
  end

  private

  def enqueue(purpose, key)
    unless @session.exercise_version.operation
      raise SessionCommandError.new("This track does not have an execution runner yet", status: :unprocessable_content)
    end
    if key.nil? || (key.respond_to?(:empty?) && key.empty?) || (key.is_a?(String) && key.blank?)
      raise SessionCommandError.new("Required request fields are missing", status: :bad_request)
    end
    unless key.is_a?(String) && key.match?(/\A[0-9a-f-]{36}\z/)
      raise SessionCommandError.new("Invalid request identifier", status: :bad_request)
    end

    @account.with_lock do
      @session.with_lock do
        @session.expire_locked!
        if purpose == "prepare" && !%w[draft preparing ready].include?(@session.status)
          raise SessionCommandError, "Preparation is only available before starting"
        end
        existing = @session.execution_requests.find_by(client_request_id: key)
        if existing
          unless existing.purpose == purpose && existing.source_snapshot.revision == @session.current_revision
            raise SessionCommandError, "Request identifier was used for different work"
          end
        else
          pending = ExecutionRequest.joins(:interview_session)
            .where(interview_sessions: { account_id: @account.id }, status: %w[queued leased]).count
          if pending >= 3
            raise SessionCommandError.new("Three executions are already pending. Wait for a worker.", status: :too_many_requests)
          end
          @session.execution_requests.create!(client_request_id: key, purpose: purpose, source_snapshot: @session.current_snapshot)
        end
        if purpose == "prepare" && (existing.nil? || %w[queued leased].include?(existing.status))
          @session.update!(status: "preparing")
        end
      end
    end
    @session
  end
end
