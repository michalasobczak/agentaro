require "test_helper"

class VoiceRecordingFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    executor = Executor.create!(name: "Claude", preset: "claude_code")
    director = Agent.create!(user: @user, name: "Director", master_prompt: "x", executor: executor)
    @user.team_roles.create!(agent: director, role: "director")
    sign_in(@user)
  end

  test "recordings are sent and saved in order beyond both former limits" do
    # The Rails callbacks capture the store on boot. Make that store count as it does in production.
    store = ApplicationController::RATE_LIMIT_STORE
    memory = ActiveSupport::Cache::MemoryStore.new
    store.define_singleton_method(:increment, memory.method(:increment).to_proc)
    original = Voice.method(:transcribe)
    transcripts = Array.new(241) { |i| "Nagranie #{i + 1}" }
    remaining = transcripts.dup
    Voice.define_singleton_method(:transcribe) { |*, **| remaining.shift }

    freeze_time do
      assert_difference -> { TaskRun.where(user: @user, purpose: "chat", state: "queued").count }, 1 do
        upload_recording
        assert_response :ok
        assert_equal transcripts.first, response.parsed_body.dig("message", "content")
        assert_equal true, response.parsed_body["writing"]
      end

      20.times do
        post chat_messages_path, params: { chat_message: { content: "Typed message", spoken: "1" } }, as: :json
        assert_response :ok
      end
      post chat_messages_path, params: { chat_message: { content: "Typed message", spoken: "1" } }, as: :json
      assert_response :too_many_requests

      transcripts.drop(1).each do |transcript|
        upload_recording
        assert_response :ok
        assert_equal transcript, response.parsed_body.dig("message", "content")
      end

      messages = @user.chat_messages.ordered
      assert_equal 20, messages.where(spoken: false).count
      assert_equal transcripts, messages.where(spoken: true, author: "user").pluck(:content)
      assert_equal 1, TaskRun.where(user: @user, purpose: "chat", state: "queued").count
    end
  ensure
    store.singleton_class.remove_method(:increment) if store
    Voice.define_singleton_method(:transcribe, original) if original
  end

  test "silent recordings are discarded without queuing a chat run" do
    original = Voice.method(:transcribe)
    Voice.define_singleton_method(:transcribe) { |*, **| "" }

    assert_no_difference [ "@user.chat_messages.count", "TaskRun.count" ] do
      upload_recording
      assert_response :ok
      assert_equal({ "ok" => true, "message" => nil }, response.parsed_body)
    end
  ensure
    Voice.define_singleton_method(:transcribe, original) if original
  end

  private

  def upload_recording
    wav = "RIFF\x26\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x80\x3e\x00\x00\x00\x7d\x00\x00\x02\x00\x10\x00data\x02\x00\x00\x00\x00\x00".b
    post voice_transcribe_path, params: wav, headers: { "Content-Type" => "audio/wav", "Accept" => "application/json" }
  end
end
