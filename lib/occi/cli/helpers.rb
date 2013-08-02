# a bunch of OCCI client helpers for bin/occi
module Occi::Cli
  module Helpers

    def helper_list(options, output = nil)
      found = []

      if resource_types.include? options.resource
        Occi::Log.debug "#{options.resource} is a resource type."
        found = list options.resource
      elsif mixin_types.include? options.resource
        Occi::Log.debug "#{options.resource} is a mixin type."
        found = mixins options.resource
      else
        Occi::Log.warn "I have no idea what #{options.resource} is ..."
        raise "Unknown resource #{options.resource}, there is nothing to list here!"
      end

      helper_list_output(found, options, output)
    end

    def helper_list_output(found, options, output)
      return found unless output

      helper_formatter_output(found, output, :locations, options.resource.to_sym)

      nil
    end

    def helper_describe(options, output = nil)
      found = []

      if resource_types.include?(options.resource) || options.resource.start_with?(options.endpoint) || options.resource.start_with?('/')
        Occi::Log.debug "#{options.resource} is a resource type or an actual resource."

        found = describe(options.resource)
      elsif mixin_types.include? options.resource
        Occi::Log.debug "#{options.resourcre} is a mixin type."

        mixins(options.resource).each do |mxn|
          mxn = mxn.split("#").last
          found << mixin(mxn, options.resource, true)
        end
      elsif mixin_types.include? options.resource.split('#').first
        Occi::Log.debug "#{options.resource} is a specific mixin type."

        mxn_type,mxn = options.resource.split('#')
        found << mixin(mxn, mxn_type, true)
      else
        Occi::Log.warn "I have no idea what #{options.resource} is ..."
        raise "Unknown resource #{options.resource}, there is nothing to describe here!"
      end

      helper_describe_output(found, options, output)
    end

    def helper_describe_output(found, options, output)
      return found unless output

      if options.resource.start_with? options.endpoint
        # resource contains full endpoint URI
        # e.g., http://localhost:3300/network/adfgadf-daf5a6df4afadf-adfad65f4ad
        resource_type = options.resource.split('/')[3].to_sym
      elsif options.resource.start_with? '/'
        # resource contains a path relative to endpoint URI
        # e.g., /network/adfgadf-daf5a6df4afadf-adfad65f4ad
        resource_type = options.resource.split('/')[1].to_sym
      elsif mixin_types.include? options.resource.split('#').first
        # resource contains a mixin with a type
        # e.g., os_tpl#debian6
        resource_type = options.resource.split('#').first.to_sym
      else
        # resource probably contains RAW resource_type
        resource_type = options.resource.to_sym
      end

      helper_formatter_output(found, output, :resources, resource_type)

      nil
    end

    def helper_create(options, output = nil)
      location = nil

      if resource_types.include? options.resource
        Occi::Log.debug "#{options.resource} is a resource type."
        raise "Not yet implemented!" unless options.resource.include? "compute"

        res = resource options.resource

        Occi::Log.debug "Creating #{options.resource}:\n#{res.inspect}"

        helper_attach_links(options, res)
        helper_attach_mixins(options, res)
        helper_attach_context_vars(options, res)

        # TODO: set other attributes
        # TODO: OCCI-OS uses occi.compute.hostname instead of title
        res.title = options.attributes[:title]
        res.hostname = options.attributes[:title]

        Occi::Log.debug "Creating #{options.resource}:\n#{res.inspect}"

        location = create res
      else
        Occi::Log.warn "I have no idea what #{options.resource} is ..."
        raise "Unknown resource #{options.resource}, there is nothing to create here!"
      end

      return location if output.nil?

      puts location
    end

    def helper_attach_links(options, res)
      return unless options.links
      Occi::Log.debug "with links: #{options.links}"

      options.links.each do |link|
        if link.start_with? options.endpoint
          link.gsub!(options.endpoint.chomp('/'), '')
        end

        if link.include? "/storage/"
          Occi::Log.debug "Adding storagelink to #{options.resource}"
          res.storagelink link
        elsif link.include? "/network/"
          Occi::Log.debug "Adding networkinterface to #{options.resource}"
          res.networkinterface link
        else
          raise "Unknown link type #{link}, stopping here!"
        end
      end
    end

    def helper_attach_mixins(options, res)
      return unless options.mixins
      Occi::Log.debug "with mixins: #{options.mixins}"

      options.mixins.keys.each do |type|
        Occi::Log.debug "Adding mixins of type #{type} to #{options.resource}"

        options.mixins[type].each do |name|
          mxn = mixin name, type

          raise "Unknown mixin #{type}##{name}, stopping here!" unless mxn
          Occi::Log.debug "Adding mixin #{mxn} to #{options.resource}"
          res.mixins << mxn
        end
      end
    end

    def helper_attach_context_vars(options, res)
      # TODO: find a better/universal way to do contextualization
      return unless options.context_vars
      Occi::Log.debug "with context variables: #{options.context_vars}"

      options.context_vars.each_pair do |var, val|
        schema = nil
        mxn_attrs = Occi::Core::Attributes.new

        case var
        when :public_key
          schema = "http://schemas.openstack.org/instance/credentials#"
          mxn_attrs['org.openstack.credentials.publickey.name'] = {}
          mxn_attrs['org.openstack.credentials.publickey.data'] = {}
        when :user_data
          schema = "http://schemas.openstack.org/compute/instance#"
          mxn_attrs['org.openstack.compute.user_data'] = {}
        else
          schema = "http://schemas.ogf.org/occi/core#"
        end

        mxn = Occi::Core::Mixin.new(schema, var.to_s, 'OS contextualization mixin', mxn_attrs)
        res.mixins << mxn

        case var
        when :public_key
          res.attributes['org.openstack.credentials.publickey.name'] = 'Public SSH key'
          res.attributes['org.openstack.credentials.publickey.data'] = val
        when :user_data
          res.attributes['org.openstack.compute.user_data'] = val
        else
          # do nothing
        end
      end
    end

    def helper_delete(options, output = nil)
      if delete(options.resource)
        Occi::Log.info "Resource #{options.resource} successfully removed!"
      else
        raise "Failed to remove resource #{options.resource}!"
      end

      true
    end

    def helper_trigger(options, output = nil)
      raise "Not yet implemented!"
    end

    def helper_formatter_output(found, output, format_symbol, resource_type)
      if Occi::Cli::ResourceOutputFactory.allowed_resource_types.include? resource_type
        puts output.format(found, format_symbol, resource_type)
      else
        Occi::Log.warn "Not printing, resource type [#{resource_type.to_s}] is not supported!"
      end
    end

  end
end
