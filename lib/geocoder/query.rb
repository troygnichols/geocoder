module Geocoder
  class Query
    attr_accessor :text, :options

    def initialize(text, options = {})
      self.text = text
      self.options = options
    end

    def execute
      found = []

      lookups.each do |lookup|
        found = lookup.search(text, options)
        break unless found.nil? || found.empty?
      end

      found
    end

    def to_s
      text
    end

    def sanitized_text
      if coordinates?
        text.split(/\s*,\s*/).join(',')
      else
        text
      end
    end

    ##
    # Get an array of Lookup objects (which communicates with the remote geocoding API)
    # appropriate to the Query text.
    #
    def lookups(options = {})
      if ip_address?
        names = Configuration.ip_lookup || Geocoder::Lookup.ip_services.first
      else
        names = Configuration.lookup || Geocoder::Lookup.street_services.first
      end

      names = [names] unless names.is_a? Array

      names.collect { |name| Lookup.get(name) }
    end

    def url
      lookup.query_url(self)
    end

    ##
    # Is the Query blank? (ie, should we not bother searching?)
    # A query is considered blank if its text is nil or empty string AND
    # no URL parameters are specified.
    #
    def blank?
      !params_given? and (
        (text.is_a?(Array) and text.compact.size < 2) or
        text.to_s.match(/\A\s*\z/)
      )
    end

    ##
    # Does the Query text look like an IP address?
    #
    # Does not check for actual validity, just the appearance of four
    # dot-delimited numbers.
    #
    def ip_address?
      !!text.to_s.match(/\A(::ffff:)?(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\z/)
    end

    ##
    # Is the Query text a loopback IP address?
    #
    def loopback_ip_address?
      !!(self.ip_address? and (text == "0.0.0.0" or text.to_s.match(/\A127/)))
    end

    ##
    # Does the given string look like latitude/longitude coordinates?
    #
    def coordinates?
      text.is_a?(Array) or (
        text.is_a?(String) and
        !!text.to_s.match(/\A-?[0-9\.]+, *-?[0-9\.]+\z/)
      )
    end

    ##
    # Return the latitude/longitude coordinates specified in the query,
    # or nil if none.
    #
    def coordinates
      sanitized_text.split(',') if coordinates?
    end

    ##
    # Should reverse geocoding be performed for this query?
    #
    def reverse_geocode?
      coordinates?
    end

    private # ----------------------------------------------------------------

    def params_given?
      !!(options[:params].is_a?(Hash) and options[:params].keys.size > 0)
    end
  end
end
