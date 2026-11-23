# Spec 053, G1: "Relaxed sandbox" for the signed-in account's command-line runs (web, local ports, Git made before a
# step); file rules stay. Recorded in the data changelog like every change (R3).
class Account::RelaxedSandboxesController < ApplicationController
  def update
    on = params[:on].to_s == "1"
    current_user.update!(relaxed_sandbox: on)
    redirect_to executors_path, notice: on ? "Relaxed sandbox on: agents may open web pages, local ports and use Git." : "Relaxed sandbox off: the strict sandbox as before."
  end
end
