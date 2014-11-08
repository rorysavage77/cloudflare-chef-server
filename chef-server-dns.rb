#!/opt/chef/embedded/bin/ruby -W0
######################################################################
## Written by: Rory Savage <rcsavage/Digital Dreams>                ##
## For use with a chef-server in Amazon AWS                         ##
## Purpose: to automatically provision a DNS entry in CloudFlare    ##
## Requires: data_bag/cloudflare                                    ##
######################################################################
require 'cloudflare'               # For access to CloudFlare
require 'chef-api'                 # For accessing Chef Data
require 'vine'	                   # Required for deep nested Hash Searching

include ChefAPI::Resource          # 
ChefAPI.log_level = :fatal         # Disable the annoying SSL warning messages


File.open(ENV['HOME']+'/.chef/knife.rb').each do |line|
    if line.match("chef_server_url"); $client_uri = line.scan(/'([^']*)'/).join(" ");  end
    if line.match("client_key");      $client_key = line.scan(/'([^']*)'/).join(" ");  end
    if line.match("node_name");       $client_node = line.scan(/'([^']*)'/).join(" "); end
  end
  connection = ChefAPI::Connection.new(
    client: $client_node,
    key: $client_key,
    ssl_verify: false,
    endpoint: $client_uri
  )

connection.data_bags.fetch('cloudflare').items.each do |item|
    if item.id == "main"
      $dssuperitem = item
    end
  end

    cf_api_key    = $dssuperitem.data.access('CLOUDFLARE_KEY')
    cf_api_user   = $dssuperitem.data.access('CLOUDFLARE_USER')

# AWS Specific Address
aws_public_ip = %x(wget -qO- http://instance-data/latest/meta-data/public-ipv4)
if !aws_public_ip.nil? || !aws_public_ip.empty?
   aws_region = %x(curl --silent http://instance-data/latest/dynamic/instance-identity/document |grep region|awk -F: '{print $2}' | cut -d'"' -f 2).strip!

      # The following block should be updated for your AWS regions/domains
      if aws_region == "us-east-2"
         chef_domain = "digitaldreams.com"
      elsif aws_region == "us-west-1"
         chef_domain = "digitalminds.com"
      elsif aws_region == "ap-southeast-1"
         chef_domain = "mindcrime.net"
      else
         chef_domain = "undefined"
      end

   puts "AWS External ip: #{aws_public_ip}"
   puts "AWS Region: #{aws_region}"
   puts "Chef Domain: #{chef_domain}"

    cf = CloudFlare::connection(cf_api_key, cf_api_user)
    begin
      all_subdomains = cf.rec_load_all chef_domain 
      sub_domain_details = all_subdomains['response']['recs']['objs'].select { |d| d['display_name'] == "chef" }
      stored_ip = sub_domain_details.first['content']
      record_id = sub_domain_details.first['rec_id']
      if stored_ip != aws_public_ip
         puts "IP Update=>#{aws_public_ip}"
           cf.rec_edit(chef_domain, 'A', record_id, "chef", aws_public_ip, 1)
      else
         puts "IP Update=>(not required)"
         exit
      end
    rescue => e
      puts e.message
    else
      puts "Complete"
    end

else
   generic_public_ip = %x(curl -s checkip.dyndns.org|sed -e 's/.*Current IP Address: //' -e 's/<.*$//')
   puts "Generic External ip: #{generic_public_ip}"
end

