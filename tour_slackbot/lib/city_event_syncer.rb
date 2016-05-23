require 'dotenv'
require 'slack-ruby-client'
require 'google_drive'
require 'utils/configure_clients'
require 'form_copy_apps_script_executor'

Dotenv.load

EVENTS_CITIES_SHEET_INDEX = 0
EVENTS_TODO_FORM_CITY_INDEX = 2
EVENTS_TODO_FORM_COL_INDEX = 8
EVENTS_TODO_RESPONSES_COL_INDEX = 9

GOOGLE_SHEET_URL_PREFIX = 'https://docs.google.com/spreadsheets/d/'

module CityEventSyncer
  extend ConfigureClients

  # Google Drive

  # Gets a hash of all cities in our Google Spreadsheet
  # Returns a hash in the format { "City Name" => "[FormID, ResponsesID]" }
  def self.get_cities
    cities_hash = {}
    session = configure_google_drive
    begin
      sheet = session.spreadsheet_by_key(ENV['EVENTS_SPREADSHEET_ID'])
        .worksheets[EVENTS_CITIES_SHEET_INDEX]
      # Get all cities
      (2..sheet.num_rows).each do |row|
        city = sheet[row, EVENTS_TODO_FORM_CITY_INDEX]
        todo_form_url = sheet[row, EVENTS_TODO_FORM_COL_INDEX]
        responses_sheet = sheet[row, EVENTS_TODO_RESPONSES_COL_INDEX]
        cities_hash[city] = [todo_form_url, responses_sheet]
      end
    rescue Exception => e
      puts "Exception: #{e}"
      puts "#{e.backtrace}"
    end

    cities_hash
  end

  # Create Google Form and Responses Sheet per-city if it doesn't already exist, add to sheet
  def self.update_sheet
    session = configure_google_drive
    form_copy_executor = configure_apps_script_executor
    begin
      sheet = session.spreadsheet_by_key(ENV['EVENTS_SPREADSHEET_ID'])
        .worksheets[EVENTS_CITIES_SHEET_INDEX]
      (2..sheet.num_rows).each do |row|
        city = sheet[row, EVENTS_TODO_FORM_CITY_INDEX]
        todo_form_url = sheet[row, EVENTS_TODO_FORM_COL_INDEX]
        responses_sheet_key = sheet[row, EVENTS_TODO_RESPONSES_COL_INDEX]
        if todo_form_url.empty? and responses_sheet_key.empty?
          responses_sheet_key = session.create_spreadsheet("#{city} BNC Tour To-Do Responses").key
          todo_form_url = form_copy_executor.copy_form(city, responses_sheet_key)
          puts "Updating #{city}\nForm: #{todo_form_url}\nResponses: #{responses_sheet_key}"
        elsif todo_form_url.empty? and not responses_sheet_key.empty?
          todo_form_url = form_copy_executor.copy_form(city, responses_sheet_key)
          puts "Updating #{city}\nForm: #{todo_form_url}\nResponses: #{responses_sheet_key}"
        elsif not todo_form_url.empty? and responses_sheet_key.empty?
          responses_sheet_key = session.create_spreadsheet("#{city} BNC Tour To-Do Responses").key
          todo_form_url = form_copy_executor.copy_form(city, responses_sheet_key)
          puts "Updating #{city}\nForm: #{todo_form_url}\nResponses: #{responses_sheet_key}"
        else
          puts "#{city} up-to-date with form #{todo_form_url} and responses sheet #{responses_sheet_key} -- nothing to do!"
        end
        responses_sheet_url = "#{GOOGLE_SHEET_URL_PREFIX}/#{responses_sheet_key}"
        sheet[row, EVENTS_TODO_FORM_COL_INDEX] = todo_form_url
        sheet[row, EVENTS_TODO_RESPONSES_COL_INDEX] = responses_sheet_url
        sheet.save
      end
    rescue Exception => e
      puts "Exception: #{e}"
      puts "#{e.backtrace}"
    end
  end

  # Slack

  # Create one private slack group for each city
  # Returns all private Slack groups names
  def self.create_groups(group_names)
    client = configure_slack
    group_names.each do |n|
      begin
        client.groups_create(name: n)
      rescue Exception => e
        puts "Error while creating channel for #{n}: #{e}"
        puts "#{e.backtrace}"
      end
    end
  end

  # Returns all groups in the format { "GroupName" => "GroupID"}
  def self.list_groups
    client = configure_slack
    begin
      groups = client.groups_list(exclude_archived: true)['groups'] || []
    rescue Exception => e
      puts "Error while getting groups list: #{e}"
      puts "#{e.backtrace}"
    end

    groups.map { |g| { g.name => g.id } }
  end

  def self.groups_set_topics(group_id_to_topic_hash)
    client = configure_slack
    group_id_to_topic_hash.each do |gid, t|
      begin
        topic = group_get_topic(gid)
        client.groups_setTopic(channel: gid, topic: t) unless topic == t
      rescue Exception => e
        puts "Error while setting topic: #{e}\nGroup: #{gid}\nTopic: #{t}"
        puts "#{e.backtrace}"
      end
    end
  end

  def self.group_get_topic(group_id)
    client = configure_slack
    begin
      t = client.groups_info(channel: group_id)['group']['topic']['value']
    rescue Exception => e
      puts "Error while getting group topic: #{e}\nGroup: #{group_id}"
      puts "#{e.backtrace}"
    end
    t
  end

  def self.slack_name_for_city_name(city_name)
    city_name.downcase.gsub(' ', '_').gsub('.', '')
  end
end
