module Voting
  # Loads config/candidates.yml and exposes the poll metadata + candidate list.
  # The YAML is the source of truth for presentation (URLs/blurbs); on-chain
  # vote counts come from Voting::CandidateAccount.
  class CandidateConfig
    Candidate = Data.define(:name, :description, :url)
    Poll      = Data.define(:id, :name, :description, :start_time, :end_time)

    class << self
      def poll
        @poll ||= Poll.new(**data.fetch("poll").symbolize_keys)
      end

      def candidates
        @candidates ||= data.fetch("candidates").map { |c| Candidate.new(**c.symbolize_keys) }
      end

      def candidate_names
        @candidate_names ||= candidates.map(&:name)
      end

      def reload!
        @data = @poll = @candidates = @candidate_names = nil
      end

      private

      def data
        @data ||= YAML.load_file(Rails.root.join("config/candidates.yml"))
      end
    end
  end
end
