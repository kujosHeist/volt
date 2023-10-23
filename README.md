# Stark Industries HQ Energy Consumption & CO2 Emissions Calculator
This script calculates how much energy (in kWh) was consumed and how much CO2 (in kgs) was produced (along with the fuel mix) by the Stark Industries HQ for a given period of time, at a granularity of 30 minutes. The data is fetched from the OpenVolt's Interval API (https://docs.openvolt.com/)  and the National Grid's Carbon Intensity & Generation Mix API (https://carbon-intensity.github.io/api-definitions).

## Dependencies
- Ruby (tested on 3.1.2 and 2.7.2) - https://www.ruby-lang.org/en/documentation/installation/
- RubyGems package manager - https://rubygems.org/pages/download

## Setup
1. Clone the repo:<br>
`git clone https://github.com/kujosHeist/volt.git`
2. Change directory<br>
`cd volt`
2. Install the required gems:<br>
`gem install rest-client`


## Usage
To run the script with the sample data (1st January - 1st of February 2023):<br>
`ruby volt.rb`

Which gives response:
```
--- Usage stats from: 2023-01-01, to: 2023-02-01 ---

1. Consumption: 100281 kWh

2. CO2: 14701.11 kg

3. Fuel breakdown: 
wind: 37.72 %
gas: 27.57 %
nuclear: 14.80 %
imports: 9.34 %
biomass: 4.54 %
hydro: 2.80 %
coal: 1.83 %
solar: 1.41 %
other: 0.00 %
```

To run the script for a specific period of time:<br>
`ruby volt.rb --use-api -s 2023-01-01 -e 2023-01-03`


To view script manual:<br>
`ruby volt.rb -h`

