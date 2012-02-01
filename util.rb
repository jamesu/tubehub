# encoding: UTF-8
require 'digest/sha1'
require 'base64'
require 'rack/utils'

module Tripcode
  TRIP_SECRET = "CHANGEME"
  TRIP_REGEXP = /^(.*?)((?<!&)#|\#)(.*)$/
  TRIP_SECURE_REGEXP = /(?:\#)(?<!&#)(?:\#)*(.*)$/

  def self.encode(name)
    if name =~ TRIP_REGEXP
      name = clean_str($1)
      marker = $2
      trippart = $3
      trip = ""

      # Extract secret tripcode part if possible
      trippart = trippart.sub(TRIP_SECURE_REGEXP, '')
      if $1
        # Secure tripcode
        puts "ITS SECURE (P=#{trippart},ch=#{$1})"
        trip = '!' + '!' + secure_encode($1[0..255], 6, "trip", TRIP_SECRET)

        return [name,trip] if trippart.empty?
      end

      # Normal tripcode
      trippart = clean_str(trippart.encode("SJIS"))
      salt = (trippart+"H..")[1..2].
      gsub(/[^\.-z]/, '.').
      tr(':;<=>?@[\\]^_`', 'ABCDEFGabcdef')

      [name, '!' + trippart.crypt(salt)[-10..-1] + trip]
    else
      [name, nil]
    end
  end

  private

  def self.clean_str(str)
    Rack::Utils.escape_html(str).gsub(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/, '')
  end

  def self.secure_encode(data, bytes, key, secret)
    secure_key = Digest::SHA1.digest(key + secret)[0...32]
    crypt = Digest::SHA1.digest(secure_key + data)[-bytes..-1]
    Base64.encode64(crypt)
  end

end

