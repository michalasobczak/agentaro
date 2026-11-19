# Spec 008, G7 (Q4): everyone signed in sees the executors read-only; admins manage them in Admin::ExecutorsController.
class ExecutorsController < ApplicationController
  def index
    @executors = Executor.ordered
  end
end
