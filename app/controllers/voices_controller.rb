# Spec 017: the director chat's voice — transcription of the user's speech and the director's spoken answer.
# Signed-in users only (ApplicationController); limited per user (R1, R2).
class VoicesController < ApplicationController
  rate_limit to: 60, within: 10.minutes, only: :transcribe, by: -> { current_user.id }, store: RATE_LIMIT_STORE,
             with: -> { render json: { error: "Too many recordings. Try again in a few minutes." }, status: :too_many_requests }
  rate_limit to: 300, within: 10.minutes, only: :speak, by: -> { current_user.id }, store: RATE_LIMIT_STORE,
             with: -> { render json: { error: "Too much speech. Try again in a few minutes." }, status: :too_many_requests }

  # Raw WAV body (audio/wav), as recorded and encoded by chat.js.
  def transcribe
    return render(json: { error: "The recording is too long." }, status: :content_too_large) if request.content_length.to_i > Voice::MAX_AUDIO

    render json: { text: Voice.transcribe(request.raw_post.to_s.b) }
  rescue Voice::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  def speak
    send_data Voice.speak(params[:text]), type: "audio/wav", disposition: "inline"
  rescue Voice::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  # What the voice button needs to know (G7).
  def status
    render json: { listening: Voice.listening?, speaking: Voice.speaking? }
  end
end
