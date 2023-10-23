require 'rest-client'
require 'json'
require 'time'
require 'optparse'

$meter_id = '6514167223e3d1424bf82742'
$x_api_key = 'test-Z9EB05N-07FMA5B-PYFEE46-X4ECYAR'

$granularity = "hh" # 30 minutes
$fuel_list = %w[biomass coal imports gas nuclear other hydro solar wind]


# @param start_date: The start date in the format 'YYYY-MM-DD'.
# @param end_date: The end date in the format 'YYYY-MM-DD'.
# 
# @return: Consumption data for the period in question at a 30-minute granularity.
def get_consumption_data_from_api(start_date, end_date)
  url = "https://api.openvolt.com/v1/interval-data"
  
  headers = {
    accept: 'application/json',
    x_api_key: $x_api_key
  }

	params = {
		meter_id: $meter_id,
		granularity: $granularity,
		start_date: start_date,
		end_date: end_date
	}  

  begin
    response = RestClient.get(url, {params: params}.merge(headers))
    JSON.parse(response.body)
  rescue RestClient::Exception => e
    raise RuntimeError, "API request failed: #{e.message}"
  rescue JSON::ParserError
    raise RuntimeError, "Failed to parse consumption API response"
  end
end


# @param start_date: The start date in the format 'YYYY-MM-DD'.
# @param end_date: The end date in the format 'YYYY-MM-DD'.
# 
# @return: Array of intensity data for each 30-minute interval.
def get_intensity_data_from_api(start_date, end_date)
	# set to 15 mins past so that correct 30 min slot is returned
	start_time = Time.iso8601("#{start_date}T00:15:00Z") 
	end_time = 	 Time.iso8601("#{end_date}T00:15:00Z")

	base_url = 'https://api.carbonintensity.org.uk/intensity'

	headers = {
  	accept: 'application/json'
	}

	begin
		data = []
		while start_time < end_time
			url = base_url + '/' + start_time.iso8601
		  response = RestClient.get(url, params: {}, headers: headers)
		  data.push(JSON.parse(response.body))
		  start_time += (30 * 60) # add 30 minutes
		end
		data
  rescue RestClient::Exception => e
    raise RuntimeError, "API request failed: #{e.message}"
  rescue JSON::ParserError
    raise RuntimeError, "Failed to parse intensity API response"
  end
end


# @param: start_date: The start date in the format 'YYYY-MM-DD'.
# @param end_date: The end date in the format 'YYYY-MM-DD'.
# 
# @return: Array of generation data for each 30-minute interval.
def get_generation_data_from_api(start_date, end_date)
	# set to 15 mins past so that correct 30 min slot is returned
	start_time = Time.iso8601("#{start_date}T00:15:00Z") 
	end_time = 	 Time.iso8601("#{end_date}T00:15:00Z")

	base_url = 'https://api.carbonintensity.org.uk/generation'

	headers = {
  	accept: 'application/json'
	}

	begin
		data = []
		while start_time < end_time
			to_time = start_time + (30 * 60)
			url = base_url + '/' + start_time.iso8601 + '/' + to_time.iso8601
		  response = RestClient.get(url, params: {}, headers: headers)	 
		  data.push(JSON.parse(response.body))
		  start_time += (30 * 60) # add 30 minutes	  
		end		
		data
  rescue RestClient::Exception => e
    raise RuntimeError, "API request failed: #{e.message}"
  rescue JSON::ParserError
    raise RuntimeError, "Failed to parse generation API response"
  end	
end


# @param file_name: File name to read the data from
# 
# @return: JSON parsed data
def get_data_from_file(file_name)
  begin
    File.open(file_name, 'r') do |file|
			JSON.parse(file.read)
    end
  rescue Errno::ENOENT
    puts "File not found"
  rescue JSON::ParserError
    puts "Error parsing JSON"
  rescue => e
    puts "Unexpected error occurred: #{e.message}"
  end
end


# @param data: An array of hashes where each hash is expected to have a structure of:
#   {
#     'data' => [
#       {
#         'intensity' => {
#           'actual' => Numeric or nil,
#           'forecast' => Numeric
#         }
#       }
#     ]
#   }
#
# @return: An array of carbon intensity values
def process_intensity_data(data)
	data.map do |item| 
		actual = item['data'][0]['intensity']['actual']
		forecast = item['data'][0]['intensity']['forecast']
		actual.nil? ? forecast : actual
	end
end


# @param data: An array of hashes where each hash is expected to have a structure of:
#   {
#     'data' => [
#       {
#         'generationmix' => [
#           {
#             'fuel' => String,
#             'perc' => Numeric
#           },
#           ... (other fuels and percentages)
#         ]
#       }
#     ]
#   }
#
# @return: An array of hashes where each hash maps a fuel type to its
# percentage value. The percentage value is normalized, i.e. a value of 0.25 represents 25%.
def process_generation_data(data)
	generation_map_array = []  # rename to include map
	data.each do |generation|
		mix = generation['data'][0]['generationmix']
		generation_map = mix.each_with_object({}) do |item, map|
		  map[item["fuel"]] = item["perc"]/100.0
		end	
		generation_map_array.push(generation_map)
	end
	generation_map_array
end


# @param consumption_array: An array integer values, each of which represents the kwh
# consumption for a specific period of time.
# @param intensity_array: An array of float values corresponding to each consumption value. 
# Each of which represents the CO2 intensity (in grams) for a specific period of time.
# 
# Both arrays must be of the same length, and each value in the `intensity_array` corresponds
# to the same value in the `consumption_array`.
#
# @return: The total CO2 consumption (kgs)
def get_total_co2_consumption(consumption_array, intensity_array)
	total_kg_co2 = 0.0
	consumption_array.each_with_index do |item, i|
		total_kg_co2 += (consumption_array[i] * intensity_array[i])/1000.0
	end
	total_kg_co2
end


# @param consumption_array: Array of consumption values.
# @param generation_map_array: Array of generation maps, where each map associates a fuel type with its consumption.
# each generation map corresponds to the consumption value at the same index
# @param total_kwh: Total kWh consumed.
# 
# @return: Map of each fuel type to its percentage in the total consumption.
def get_fuel_mix(consumption_array, generation_map_array, total_kwh)
	fuel_mix = {}
	$fuel_list.each do |fuel|
		fuel_mix[fuel] = 0.0
	end

	generation_map_array.each_with_index do |item, i|
		# for each fuel type, multiple it by the consumption for that half an hour period
		# then sum the total for each fuel over the entire time range
		$fuel_list.each do |fuel|
			fuel_mix[fuel] += (consumption_array[i] * generation_map_array[i][fuel] )
		end
	end
	
	fuel_percentage_map = {}
	$fuel_list.each do |fuel|
		fuel_percentage = ((fuel_mix[fuel] / total_kwh) * 100)
		fuel_percentage_map[fuel] = fuel_percentage
	end
	fuel_percentage_map
end


def parse_command_line_options
	options = {}
	OptionParser.new do |opts|
	  opts.banner = "Usage: To use sample data (from January 2023): `ruby volt.rb`, 
	  or to define your own period: `ruby volt.rb --use-api -s 2023-01-01 -e 2023-01-03`\n"

		opts.separator ""
	  api_text = "Retrieves a fresh copy of the data via api (it can take 5 or 6 mins for one month of data), when not passed it
	  defaults to using stored responses to avoid excessive api use"
	  opts.on("-a", "--use-api", api_text) do
	    options[:use_api] = true
	  end
	  
	  opts.separator ""
	  start_date_text = "Start date, format: YYYY-MM-DD, defaults to: 2023-01-01 (only valid when using api)"
	  opts.on("-s", "--start-date DATE", String, start_date_text) do |start_date|
	    options[:start_date] = start_date
	  end
	  
	  opts.separator ""
	  end_date_text = "End date, format: YYYY-MM-DD, defaults to: 2023-02-01 (only valid when using api)"
	  opts.on("-e", "--end-date DATE", String, end_date_text) do |end_date|
	    options[:end_date] = end_date
	  end
	  
	  opts.separator ""
	  help_text = "Program to calculate how much energy (kWh) was used and CO2 (kgs) created (along with the related fuel mix) 
	  by Stark Industries HQ for a given period of time (in days), at a set granularity (30 mins), Uses Open volts interval api 
	  (https://docs.openvolt.com/) and the national grids carbon intensity and generation mix api (https://carbon-intensity.github.io/api-definitions)"

	  opts.on("-h", "--help", help_text) do
	    puts opts
	    exit
	  end

	end.parse!
	options
end


if __FILE__ == $0
	options = parse_command_line_options
	
	use_api = options[:use_api]
	start_date = options[:start_date] ? options[:start_date] : "2023-01-01"
	end_date = options[:end_date] ? options[:end_date] : "2023-02-01"


	puts "Gathering consumption data..."
	if use_api
		data = get_consumption_data_from_api(start_date, end_date)
	else
		data = get_data_from_file('half_hourly_consumption.json')
	end
	data = data['data'][0...-1] # don't include the last item as it overshoots the date range
	consumption_array = data.map { |item| item['consumption'].to_i }
	
	puts "Gathering intensity data..."
	if use_api
		data = get_intensity_data_from_api(start_date, end_date)
	else
		data = get_data_from_file("half_hourly_intensity.json")
	end
	intensity_array = process_intensity_data(data)

	puts "Gathering generation data..."
	if use_api
		data = get_generation_data_from_api(start_date, end_date)
	else
		data = get_data_from_file("half_hourly_generation.json")
	end
	generation_map_array = process_generation_data(data)

	puts "\n--- Usage stats from: #{start_date}, to: #{end_date} ---"

	total_kwh = consumption_array.sum
	puts "\n1. Consumption: #{total_kwh.to_s} kWh"

	total_co2 = get_total_co2_consumption(consumption_array, intensity_array)
	puts "\n2. CO2: #{sprintf('%.2f', total_co2)} kg"
	
	puts "\n3. Fuel breakdown: "
	fuel_percentage_map = get_fuel_mix(consumption_array, generation_map_array, total_kwh)
	sorted_map = fuel_percentage_map.sort_by { |key, value| value }.reverse
	sorted_map.each do |fuel, percentage|
		puts "#{fuel}: #{sprintf('%.2f', percentage)} %"	
	end
	puts ""
end

