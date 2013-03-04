# -*- coding: utf-8 -*-
require 'geocoder/sql'
require 'geocoder/stores/base'

##
# Add geocoding functionality to any ActiveRecord object.
#
module Geocoder::Store
  module ActiveRecord
    include Base

    ##
    # Implementation of 'included' hook method.
    #
    def self.included(base)
      base.extend ClassMethods
      base.class_eval do

        def self.through_tables
          tbls = nil
          unless geocoder_options[:through].nil?

            unless geocoder_options[:through_tables].nil?
              tbls = geocoder_options[:through_tables]
            else
              through_ars = []
              through = geocoder_options[:through]
              while !through.nil? do
                through_ars << through
                through = through.klass.geocoder_options[:through]
              end

              tbls = through_ars.pop.name
              through_ars.reverse.each do |ar|
                tbls = { ar.name => tbls }
              end

              geocoder_options.merge!(:through_tables => tbls)
            end
          end
          tbls
        end

        # scope: joins table if necessary
        scope :joins_through, lambda {
          joins(through_tables) unless geocoder_options[:through].nil?
        }

        # scope: geocoded objects
        scope :geocoded, lambda {
          joins_through.where("#{geocoder_options[:latitude]} IS NOT NULL " +
            "AND #{geocoder_options[:longitude]} IS NOT NULL")
        }

        # scope: not-geocoded objects
        scope :not_geocoded, lambda {
          joins_through.where("#{geocoder_options[:latitude]} IS NULL " +
            "AND #{geocoder_options[:longitude]} IS NULL")
        }


        ##
        # Find all objects within a radius of the given location.
        # Location may be either a string to geocode or an array of
        # coordinates (<tt>[lat,lon]</tt>). Also takes an options hash
        # (see Geocoder::Orm::ActiveRecord::ClassMethods.near_scope_options
        # for details).
        #
        scope :near, lambda{ |location, *args|

          # init through path for near_scope_options function
          through_tables

          latitude, longitude = Geocoder::Calculations.extract_coordinates(location)
          if Geocoder::Calculations.coordinates_present?(latitude, longitude)
            near_scope_options(latitude, longitude, *args).joins_through
          else
            # If no lat/lon given we don't want any results, but we still
            # need distance and bearing columns so you can add, for example:
            # .order("distance")
            joins_through.select(select_clause(nil, "NULL", "NULL")).where(false_condition)
          end
        }

        ##
        # Find all objects within the area of a given bounding box.
        # Bounds must be an array of locations specifying the southwest
        # corner followed by the northeast corner of the box
        # (<tt>[[sw_lat, sw_lon], [ne_lat, ne_lon]]</tt>).
        #
        scope :within_bounding_box, lambda{ |bounds|
          sw_lat, sw_lng, ne_lat, ne_lng = bounds.flatten if bounds
          if sw_lat && sw_lng && ne_lat && ne_lng
            joins_through.where(Geocoder::Sql.within_bounding_box(
              sw_lat, sw_lng, ne_lat, ne_lng,
              full_column_name(geocoder_options[:latitude], geocoder_options[:through_tables]),
              full_column_name(geocoder_options[:longitude], geocoder_options[:through_tables])
            ))
          else
            joins_through.select(select_clause(nil, "NULL", "NULL")).where(false_condition)
          end
        }
      end
    end

    ##
    # Methods which will be class methods of the including class.
    #
    module ClassMethods

      def distance_from_sql(location, *args)
        latitude, longitude = Geocoder::Calculations.extract_coordinates(location)
        if Geocoder::Calculations.coordinates_present?(latitude, longitude)
          distance_sql(latitude, longitude, *args)
        end
      end

      private # ----------------------------------------------------------------

      ##
      # Get options hash suitable for passing to ActiveRecord.find to get
      # records within a radius (in kilometers) of the given point.
      # Options hash may include:
      #
      # * +:units+   - <tt>:mi</tt> or <tt>:km</tt>; to be used.
      #   for interpreting radius as well as the +distance+ attribute which
      #   is added to each found nearby object.
      #   Use Geocoder.configure[:units] to configure default units.
      # * +:bearing+ - <tt>:linear</tt> or <tt>:spherical</tt>.
      #   the method to be used for calculating the bearing (direction)
      #   between the given point and each found nearby point;
      #   set to false for no bearing calculation. Use
      #   Geocoder.configure[:distances] to configure default calculation method.
      # * +:select+          - string with the SELECT SQL fragment (e.g. “id, name”)
      # * +:select_distance+ - whether to include the distance alias in the
      #                        SELECT SQL fragment (e.g. <formula> AS distance)
      # * +:select_bearing+  - like +:select_distance+ but for bearing.
      # * +:order+           - column(s) for ORDER BY SQL clause; default is distance;
      #                        set to false or nil to omit the ORDER BY clause
      # * +:exclude+         - an object to exclude (used by the +nearbys+ method)
      #
      def near_scope_options(latitude, longitude, radius = 20, options = {})
        options[:units] ||= (geocoder_options[:units] || Geocoder.config.units)
        select_distance = options.fetch(:select_distance, true)
        options[:order] = "" if !select_distance && !options.include?(:order)
        select_bearing = options.fetch(:select_bearing, true)
        bearing = bearing_sql(latitude, longitude, options)
        distance = distance_sql(latitude, longitude, options)

        b = Geocoder::Calculations.bounding_box([latitude, longitude], radius, options)
        args = b + [
          full_column_name(geocoder_options[:latitude], geocoder_options[:through_tables]),
          full_column_name(geocoder_options[:longitude], geocoder_options[:through_tables])
        ]
        bounding_box_conditions = Geocoder::Sql.within_bounding_box(*args)

        if using_sqlite?
          conditions = bounding_box_conditions
        else
          conditions = [bounding_box_conditions + " AND #{distance} <= ?", radius]
        end

        select(select_clause(options[:select], select_distance ? distance : nil, select_bearing ? bearing : nil))
          .where(add_exclude_condition(conditions, options[:exclude]))
          .order(options.include?(:order) ? options[:order] : "distance ASC")
      end

      ##
      # SQL for calculating distance based on the current database's
      # capabilities (trig functions?).
      #
      def distance_sql(latitude, longitude, options = {})
        method_prefix = using_sqlite? ? "approx" : "full"
        Geocoder::Sql.send(
          method_prefix + "_distance",
          latitude, longitude,
          full_column_name(geocoder_options[:latitude], geocoder_options[:through_tables]),
          full_column_name(geocoder_options[:longitude], geocoder_options[:through_tables]),
          options
        )
      end

      ##
      # SQL for calculating bearing based on the current database's
      # capabilities (trig functions?).
      #
      def bearing_sql(latitude, longitude, options = {})
        if !options.include?(:bearing)
          options[:bearing] = Geocoder.config.distances
        end
        if options[:bearing]
          method_prefix = using_sqlite? ? "approx" : "full"
          Geocoder::Sql.send(
            method_prefix + "_bearing",
            latitude, longitude,
            full_column_name(geocoder_options[:latitude], geocoder_options[:through_tables]),
            full_column_name(geocoder_options[:longitude], geocoder_options[:through_tables]),
            options
          )
        end
      end

      ##
      # Generate the SELECT clause.
      #
      def select_clause(columns, distance = nil, bearing = nil)
        if columns == :id_only
          return full_column_name(primary_key)
        elsif columns == :geo_only
          clause = ""
        else
          if columns
            clause = columns
          else
            clause_arr = [full_column_name('*')]
            unless geocoder_options[:through].nil?
              clause_arr << full_column_name(geocoder_options[:latitude], geocoder_options[:through_tables])
              clause_arr << full_column_name(geocoder_options[:longitude], geocoder_options[:through_tables])
            end
            clause = clause_arr.join(',')
          end
        end
        if distance
          clause += ", " unless clause.empty?
          clause += "#{distance} AS distance"
        end
        if bearing
          clause += ", " unless clause.empty?
          clause += "#{bearing} AS bearing"
        end
        clause
      end

      ##
      # Adds a condition to exclude a given object by ID.
      # Expects conditions as an array or string. Returns array.
      #
      def add_exclude_condition(conditions, exclude)
        conditions = [conditions] if conditions.is_a?(String)
        if exclude
          conditions[0] << " AND #{full_column_name(primary_key)} != ?"
          conditions << exclude.id
        end
        conditions
      end

      def using_sqlite?
        connection.adapter_name.match /sqlite/i
      end

      ##
      # Value which can be passed to where() to produce no results.
      #
      def false_condition
        using_sqlite? ? 0 : "false"
      end

      ##
      # Retrieve last table joined, to extract latitude informations
      #
      def last_through_table(obj)
        obj.is_a?(Hash) ? last_through_table(obj.flatten.last) : obj
      end

      ##
      # Prepend table name if column name doesn't already contain one.
      #
      def full_column_name(column, through_tables = nil)
        column = column.to_s
        through_table_name = through_tables.nil? ? table_name : last_through_table(through_tables).to_s.pluralize
        column.include?(".") ? column : [through_table_name, column].join(".")
      end
    end

    ##
    # Look up coordinates and assign to +latitude+ and +longitude+ attributes
    # (or other as specified in +geocoded_by+). Returns coordinates (array).
    #
    def geocode
      target = self.class.geocoder_options[:through].nil? ? self : self.send(self.class.geocoder_options[:through].name)
      do_lookup(false) do |o,rs|
        if r = rs.first
          unless r.latitude.nil? or r.longitude.nil?
            o.__send__  "#{target.class.geocoder_options[:latitude]}=",  r.latitude
            o.__send__  "#{target.class.geocoder_options[:longitude]}=", r.longitude
          end
          r.coordinates
        end
      end
    end

    alias_method :fetch_coordinates, :geocode

    ##
    # Look up address and assign to +address+ attribute (or other as specified
    # in +reverse_geocoded_by+). Returns address (string).
    #
    def reverse_geocode
      do_lookup(true) do |o,rs|
        if r = rs.first
          unless r.address.nil?
            o.__send__ "#{self.class.geocoder_options[:fetched_address]}=", r.address
          end
          r.address
        end
      end
    end

    alias_method :fetch_address, :reverse_geocode
  end
end
