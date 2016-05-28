require 'city_event_syncer'
require 'form_copy_apps_script_executor'
require 'dotenv'

Dotenv.load

namespace :events do

	# Calls the Google Drive spreadsheet containing Events,
	# For each city, checks to see if we already have a TODO Form
	# and Responses sheet created for it. If we don't, creates it.
	#
	# This method is idempotent; If nothing to do, it will just be a no-op
	desc 'Syncs Events sheet, for each city, creates a TODO form and responses sheet if needed, creates a Slack channel if needed, and sets the TODO form as the topic in the Slack channel'
	task :sync do
		puts "Reading cities from the Events spreadsheet..."
		CityEventSyncer.update_sheet
		cities_hash = CityEventSyncer.get_cities
		if cities_hash and not cities_hash.empty?
			puts "Found #{cities_hash.keys[0]}..."
		else
			puts "Didn't find any cities."
		end
		slack_groups_hash = {}
		cities_hash.each do |city, value_list| # value_list is [FormURL, SheetURL]
			slack_group_name = CityEventSyncer.slack_name_for_city_name(city)
			todo_form_url = value_list[0]
			slack_groups_hash[slack_group_name] = todo_form_url
		end
		puts "Creating private Slack groups if they don't already exist..."
		CityEventSyncer.create_groups cities_hash.keys
		if cities_hash and not cities_hash.empty?
			puts "Created groups #{cities_hash.keys[0]}..."
		else
			puts "No groups to create."
		end
		group_id_hash = CityEventSyncer.list_groups
		group_todo_form_hash = {}
		group_id_hash.each do |group_name, id|
			todo_form_url = slack_groups_hash[group_name]
			group_todo_form_hash[id] = "#{CityEventSyncer::CITY_EVENT_SYNCER_TOPIC_PREFIX} #{todo_form_url}"
		end
		puts "Inviting the bot to the groups..."
		CityEventSyncer.groups_invite_bot group_id_hash.values
		puts "Invited #{group_id_hash.values[0]}..." if group_id_hash and not group_id_hash.empty?
		puts "Setting the Form as topic in Slack room if it's not already..."
		CityEventSyncer.groups_set_topics group_todo_form_hash
		puts "Set topic #{group_todo_form_hash.values[0]} in room #{group_todo_form_hash.keys[0]}" if group_todo_form_hash and not group_todo_form_hash.empty?
	end

	desc 'Updates the Google Sheet with a new prefilled URL based on the latest responses of a given form'
	task :update_prefilled_url, :form_id do |t, args|
		formId = args[:form_id]
		raise "Can't update prefilled url without formId" if formId.empty?
		begin
			CityEventSyncer.update_sheet_with_updated_prefilled_url(formId)
		rescue Exception => e
			puts "Error updating sheet with prefilled url: #{e.backtrace}"
		end
	end

	desc 'Lists all the cities, forms, and response ids in the Events spreadsheet, in the format { "City Name" => "[FormID, ResponsesID]" }'
	task :get_cities do
		puts CityEventSyncer.get_cities
	end

	desc 'Lists all the private groups in the Slack team'
	task :list_groups do
		puts CityEventSyncer.list_groups
	end

	desc 'Creates groups from a list of comma-separated group_names'
	task :create_groups, :group_names do |t, args|
		names = args[:group_names].split(',')
		raise "Can't create group names, groups empty" if names.empty?
		CityEventSyncer.create_groups names
	end

end