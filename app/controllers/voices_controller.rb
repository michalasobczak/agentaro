# Spec 017: speech synthesis and voice settings for the director chat.
class VoicesController < ApplicationController
  rate_limit to: 300, within: 10.minutes, only: :speak, by: -> { current_user.id }, store: RATE_LIMIT_STORE,
             with: -> { render json: { error: "Too much speech. Try again in a few minutes." }, status: :too_many_requests }

  def speak
    send_data Voice.speak(params[:text], language: current_user.chat_language, speaker: params[:speaker], speed: current_user.speech_speed.to_f,
                          natural: ConversationMode.natural?(current_user)), # spec 046, G3
              type: "audio/wav", disposition: "inline"
  rescue Voice::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  # Owner fix after spec 017: Auto / PL / EN for the chat with the director (recognition, replies, voice).
  def language
    current_user.update!(chat_language: params[:language]) if User::CHAT_LANGUAGES.key?(params[:language])
    redirect_back_or_to director_path
  end

  # What the voice button needs to know (G7).
  def status
    render json: { listening: Voice.listening?, speaking: Voice.speaking? }
  end
end
