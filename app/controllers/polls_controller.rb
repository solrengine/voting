class PollsController < ApplicationController
  def show
    @snapshot = Voting::PollSnapshot.current
    respond_to do |format|
      format.html
      format.json { render json: @snapshot.as_json }
    end
  end
end
