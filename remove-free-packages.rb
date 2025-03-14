require 'httparty'
require 'nokogiri'
require 'io/console'

# Configuration
STEAM_LOGIN_URL = "https://store.steampowered.com/login/"
STEAM_LICENSES_URL = "https://store.steampowered.com/account/licenses/"
STEAM_REMOVE_LICENSE_URL = "https://store.steampowered.com/account/removelicense"

# Load proxies from proxies.txt
PROXIES = File.readlines('proxies.txt').map(&:chomp)

# Headers to mimic a real browser
HEADERS = {
  "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
}

def login_to_steam(session, username, password, proxy)
  # Get the login page to retrieve the necessary cookies and form data
  response = session.get(STEAM_LOGIN_URL, headers: HEADERS, proxy: proxy)
  doc = Nokogiri::HTML(response.body)

  # Extract the required form data
  form = doc.at_css("#login_form")
  raise "Login form not found!" unless form

  form_data = {}
  form.css('input').each do |input|
    form_data[input['name']] = input['value'] if input['name']
  end

  # Add credentials to the form data
  form_data['username'] = username
  form_data['password'] = password

  # Submit the login form
  login_response = session.post(STEAM_LOGIN_URL, body: form_data, headers: HEADERS, proxy: proxy)

  # Handle 2FA if required
  if login_response.body.include?("twofactorcode")
    puts "2FA code required. Check your Steam Guard app."
    print "Enter 2FA code: "
    twofactor_code = gets.chomp
    form_data['twofactorcode'] = twofactor_code
    login_response = session.post(STEAM_LOGIN_URL, body: form_data, headers: HEADERS, proxy: proxy)
  end

  # Check if login was successful
  if login_response.body.include?("Login")
    raise "Login failed! Check your credentials or 2FA code."
  end

  session
end

def get_licenses(session, proxy)
  response = session.get(STEAM_LICENSES_URL, headers: HEADERS, proxy: proxy)
  doc = Nokogiri::HTML(response.body)

  licenses = []
  doc.css('.account_table tr').each do |row|
    cols = row.css('td')
    next if cols.size < 2

    license_name = cols[0].text.strip
    license_type = cols[1].text.strip
    licenses << license_name if license_type.downcase.include?("free")
  end

  licenses
end

def remove_license(session, license_name, proxy)
  payload = {
    "packageid" => license_name,
    "sessionid" => session.cookies["sessionid"]
  }
  response = session.post(STEAM_REMOVE_LICENSE_URL, body: payload, headers: HEADERS, proxy: proxy)

  if response.code == 200
    puts "Removed license: #{license_name}"
  else
    puts "Failed to remove license: #{license_name}"
  end
end

def main
  # Get credentials from the user
  print "Enter your Steam username: "
  username = gets.chomp
  print "Enter your Steam password: "
  password = STDIN.noecho(&:gets).chomp
  puts

  # Rotate proxies
  PROXIES.each do |proxy|
    proxy_url = "http://#{proxy}"
    puts "Using proxy: #{proxy_url}"

    # Create a session
    session = HTTParty::Session.new
    session.headers.update(HEADERS)

    # Log in to Steam
    begin
      session = login_to_steam(session, username, password, proxy_url)
    rescue => e
      puts "Error logging in: #{e.message}"
      next
    end

    # Get the list of free licenses
    licenses = get_licenses(session, proxy_url)
    if licenses.empty?
      puts "No free licenses found."
      break
    end

    # Remove each free license
    licenses.each do |license_name|
      remove_license(session, license_name, proxy_url)
    end

    break # Exit after processing one proxy
  end
end

main