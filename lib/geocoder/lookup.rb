module Geocoder
  module Lookup
    extend self

    ##
    # Array of valid Lookup service names.
    #
    def all_services
      street_services + ip_services
    end

    ##
    # Array of valid Lookup service names, excluding :test.
    #
    def all_services_except_test
      all_services - [:test]
    end

    ##
    # All street address lookup services, default first.
    #
    def street_services
      @street_services ||= begin
        street_services = [
          :dstk,
          :esri,
          :google,
          :google_premier,
          :google_places_details,
          :yahoo,
          :bing,
          :geocoder_ca,
          :geocoder_us,
          :yandex,
          :nominatim,
          :mapquest,
          :opencagedata,
          :ovi,
          :here,
          :baidu,
          :geocodio,
          :smarty_streets,
          :okf,
          :postcode_anywhere_uk,
          :test
        ]
        merge_lookups(street_services, Geocoder::Configuration.lookup)
      end
    end

    ##
    # All IP address lookup services, default first.
    #
    def ip_services
      @ip_services ||= begin
        ip_services = [
          :baidu_ip,
          :freegeoip,
          :geoip2,
          :maxmind,
          :maxmind_local,
          :telize,
          :pointpin,
          :maxmind_geoip2
        ]
        merge_lookups(ip_services, Geocoder::Configuration.ip_lookup)
      end
    end

    attr_writer :street_services, :ip_services

    ##
    # Retrieve a Lookup object from the store.
    # Use this instead of Geocoder::Lookup::X.new to get an
    # already-configured Lookup object.
    #
    def get(name)
      @services = {} unless defined?(@services)
      @services[name] = spawn(name) unless @services.include?(name)
      @services[name]
    end


    private # -----------------------------------------------------------------

    ##
    # Merge base lookups and custom configured ones
    #
    def merge_lookups(included_services, configured_services)
      services = included_services

      custom_services = configured_services
      custom_services = [custom_services] unless custom_services.is_a? Array
      services = (custom_services + services).uniq

      services
    end

    ##
    # Spawn a Lookup of the given name.
    #
    def spawn(name)
      Geocoder::Lookup.const_get(classify_name(name)).new
    rescue NameError
      valids = all_services.map(&:inspect).join(", ")
      raise ConfigurationError, "Cannot instantiate #{name.inspect} geocoder.  " +
        "Please make sure the 'lookup' config option is set to a valid type of gecoder, e.g. one of: #{valids}"
    end

    ##
    # Convert an "underscore" version of a name into a "class" version.
    #
    def classify_name(filename)
      filename.to_s.split("_").map{ |i| i[0...1].upcase + i[1..-1] }.join
    end
  end
end

Geocoder::Lookup.all_services.each do |name|
  require "geocoder/lookups/#{name}"
end
