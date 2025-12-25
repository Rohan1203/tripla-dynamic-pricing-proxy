namespace :rates do
  desc "Retrieve rates every 5 minutes"
  task retrieve_loop: :environment do
    RateRetrievalLoop.start
  end
end
