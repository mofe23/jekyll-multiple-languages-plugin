=begin

Jekyll  Multiple  locales  is  an  internationalization  plugin for Jekyll. It
compiles  your  Jekyll site for one or more locales with a similar approach as
Rails does. The different sites will be stored in sub folders with the same name
as the locale it contains.

Please visit https://github.com/screeninteraction/jekyll-multiple-locales-plugin
for more details.

=end



require_relative "plugin/version"

def translate_url(site, namespace, locale_param, strip_locale=false)
  current_locale    = site.config['locale']
  locale            = locale_param || current_locale
  is_default_locale = site.config['is_default_locale']
  baseurl           = site.baseurl
  pages             = site.pages
  url               = "";

  if (locale_param && !strip_locale) || (!locale_param && !is_default_locale )
    baseurl = baseurl + "/" + locale
  end

  collections = site.collections.values.collect{|x| x.docs}.flatten
  pages = pages + collections

  for p in pages
    unless             p['namespace'].nil?
      page_namespace = p['namespace']

      if namespace == page_namespace
        permalink = p['permalink_'+locale] || p['permalink']
        url       = baseurl + permalink
      end
    end
  end

  url

end

module Jekyll

  #*****************************************************************************
  # :site, :post_render hook
  #*****************************************************************************
  Jekyll::Hooks.register :site, :pre_render do |site, payload|
      locale = site.config['locale']
      puts "Loading translation from file #{site.source}/_i18n/#{locale}.yml"
      site.parsed_translations[locale] = YAML.load_file("#{site.source}/_i18n/#{locale}.yml")
  end

  #*****************************************************************************
  # :site, :post_write hook
  #*****************************************************************************
  Jekyll::Hooks.register :site, :post_write do |site|

    # Moves excluded paths from the default locale subfolder to the root folder
    #===========================================================================
    default_locale = site.config["default_locale"]
    current_locale = site.config["locale"]
    exclude_paths = site.config["exclude_from_localizations"]

    if (default_locale == current_locale && site.config["default_locale_in_subfolder"])
      files = Dir.glob(File.join("_site/" + current_locale + "/", "*"))
      files.each do |file_path|
        parts = file_path.split('/')
        f_path = parts[2..-1].join('/')
        if (f_path == 'base.html')
          new_path = parts[0] + "/index.html"
          puts "Moving '" + file_path + "' to '" + new_path + "'"
          File.rename file_path, new_path
        else
          exclude_paths.each do |exclude_path|
            if (exclude_path == f_path)
              new_path = parts[0] + "/" + f_path
              puts "Moving '" + file_path + "' to '" + new_path + "'"
              if (Dir.exists?(new_path))
                FileUtils.rm_r new_path
              end
              File.rename file_path, new_path
            end
          end
        end
      end
    end

    #===========================================================================

  end

  Jekyll::Hooks.register :site, :post_render do |site, payload|
    
    # Removes all static files that should not be copied to translated sites.
    #===========================================================================
    default_locale  = payload["site"]["default_locale"]
    current_locale  = payload["site"][        "locale"]
    
    static_files  = payload["site"]["static_files"]
    exclude_paths = payload["site"]["exclude_from_localizations"]
    
    default_locale_in_subfolder = site.config["default_locale_in_subfolder"]
    
    if default_locale != current_locale
      static_files.delete_if do |static_file|
        next true if (static_file.name == 'base.html' && default_locale_in_subfolder)

        # Remove "/" from beginning of static file relative path
        if static_file.instance_variable_get(:@relative_path) != nil
          static_file_r_path = static_file.instance_variable_get(:@relative_path).dup
          if static_file_r_path
            static_file_r_path[0] = ''

            exclude_paths.any? do |exclude_path|
              Pathname.new(static_file_r_path).descend do |static_file_path|
                break(true) if (Pathname.new(exclude_path) <=> static_file_path) == 0
              end
            end
          end
        end
      end
    end
    
    #===========================================================================
    
  end



  ##############################################################################
  # class Site
  ##############################################################################
  class Site
    
    attr_accessor :parsed_translations   # Hash that stores parsed translations read from YAML files.
    
    alias :process_org :process
    
    #======================================
    # process
    #
    # Reads Jekyll and plugin configuration parameters set on _config.yml, sets
    # main parameters and processes the website for each locale.
    #======================================
    def process
      # Check if plugin settings are set, if not, set a default or quit.
      #-------------------------------------------------------------------------
      self.parsed_translations ||= {}
      
      self.config['exclude_from_localizations'] ||= []

      self.config['default_locale_in_subfolder'] ||= false
      
      if ( !self.config['locales']         or
            self.config['locales'].empty?  or
           !self.config['locales'].all?
         )
          puts 'You must provide at least one locale using the "locales" setting on your _config.yml.'
          
          exit
      end
      
      
      # Variables
      #-------------------------------------------------------------------------
      
      # Original Jekyll configurations
      baseurl_org                 = self.config[ 'baseurl' ].to_s # Baseurl set on _config.yml
      dest_org                    = self.dest                     # Destination folder where the website is generated
      
      # Site building only variables
      locales                     = self.config['locales'] # List of locales set on _config.yml


      # Site wide plugin configurations
      self.config['default_locale'] = locales.first            # Default locale (first locale of array set on _config.yml)
      self.config[  'baseurl_root'] = baseurl_org              # Baseurl of website root (without the appended locale code)
      self.config[  'translations'] = self.parsed_translations # Hash that stores parsed translations read from YAML files. Exposes this hash to Liquid.


      # Build the website for default locale
      #-------------------------------------------------------------------------
      locale                      = locales.first
      parts                       = locale.split("-")
      language                    = parts.shift
      territory                   = parts.shift
      locale_underscore           = locale.dup
      locale_underscore.sub! "-", "_"

      self.config[           'locale'] = locale
      self.config['locale_underscore'] = locale_underscore
      self.config[             'lang'] = language
      self.config[        'territory'] = territory
      self.config['is_default_locale'] = true

      puts "Building default site for default language: \"#{language}\" and territory: \"#{territory}\" to: #{self.dest}"
      process_org

      # Build the website for non-default locales
      #-------------------------------------------------------------------------
      
      # Remove .htaccess file from included files, so it wont show up on translations folders.
      self.include -= [".htaccess"]
      
      locales.drop(1).each do |locale|
        
        # locale specific config/variables
        parts                            = locale.split("-")
        language                         = parts.shift
        territory                        = parts.shift
        locale_underscore                = locale.dup
        locale_underscore.sub! "-", "_"

        @dest                            = dest_org    + "/" + locale
        self.config[          'baseurl'] = baseurl_org + "/" + locale
        self.config[           'locale'] = locale
        self.config['locale_underscore'] = locale_underscore
        self.config[             'lang'] = language
        self.config[        'territory'] = territory
        self.config['is_default_locale'] = false

        puts "Building site for language: \"#{language}\" and territory: \"#{territory}\" to: #{self.dest}"
        
        process_org
      end
      
      # Revert to initial Jekyll configurations (necessary for regeneration)
      self.config[ 'baseurl' ] = baseurl_org  # Baseurl set on _config.yml
      @dest                    = dest_org     # Destination folder where the website is generated
      
      puts 'Build complete'
    end
  end



  ##############################################################################
  # class PageReader
  ##############################################################################
  class PageReader
    alias :read_org :read

    #======================================
    # read
    #
    # Monkey patched this method to remove excluded locales.
    #======================================
    def read(files)
      read_org(files).reject do |page|
        page.data['locales'] && !page.data['locales'].include?(site.config['locale'])
      end
    end
  end



  ##############################################################################
  # class PostReader
  ##############################################################################
  class PostReader
     alias :read_posts_org :read_posts

    #======================================
    # read_posts
    #======================================
    def read_posts(dir)
      translate_posts = !site.config['exclude_from_localizations'].include?("_posts")
      if dir == '' && translate_posts
        read_posts("_i18n/#{site.config['locale']}/")
      else
        read_posts_org(dir)
      end
    end
  end
  
  
  
  #-----------------------------------------------------------------------------
  #
  # Include (with priority—prepend)the translated
  # permanent link for Page and document
  #
  #-----------------------------------------------------------------------------

  module Permalink
    #======================================
    # permalink
    #======================================
    def permalink
      return nil if data.nil? || data['permalink'].nil?
      
      if site.config['relative_permalinks']
        File.join(@dir,  data['permalink'])
      elsif site.config['locale']
        # Look if there's a permalink overwrite specified for this locale
        data['permalink_' + site.config['locale']] || data['permalink']
      else
        data['permalink']
      end
      
    end
  end

  Page.prepend(Permalink)
  Document.prepend(Permalink)


  ##############################################################################
  # class Document
  ##############################################################################
  class Document
    alias :populate_categories_org :populate_categories
      
    #======================================
    # populate_categories
    #
    # Monkey patched this method to remove unwanted strings
    # ("_i18n" and locale code) that are prepended to posts categories
    # because of how the multilingual posts are arranged in subfolders.
    #======================================
    def populate_categories
      data['categories'].delete("_i18n")
      data['categories'].delete(site.config['locale'])

      merge_data!({
        'categories' => (
          Array(data['categories']) + Utils.pluralized_array_from_hash(data, 'category', 'categories')
        ).map(&:to_s).flatten.uniq
      })
    end
  end
  
  
  
  #-----------------------------------------------------------------------------
  #
  # The next classes implements the plugin Liquid Tags and/or Filters
  #
  #-----------------------------------------------------------------------------


  ##############################################################################
  # class LocalizeTag
  #
  # Localization by getting localized text from YAML files.
  # User must use the "t" or "translate" liquid tags.
  ##############################################################################
  class LocalizeTag < Liquid::Tag
  
    #======================================
    # initialize
    #======================================
    def initialize(tag_name, key, tokens)
      super
      @key = key.strip
    end
    
    #======================================
    # render
    #======================================
    def render(context)
      if      "#{context[@key]}" != "" # Check for page variable
        key = "#{context[@key]}"
      else
        key =            @key
      end
      
      key = Liquid::Template.parse(key).render(context)  # Parses and renders some Liquid syntax on arguments (allows expansions)
      
      site = context.registers[:site] # Jekyll site object
      
      locale = site.config['locale']
      
      get_translation(site, locale, key)
    end

    def get_translation(site, locale, key)
      translation = site.parsed_translations[locale].access(key) if key.is_a?(String) and site.parsed_translations[locale]

      if translation.nil? or translation.empty?
        lang = locale.split("-").shift
        if lang != locale and site.config['locales'].include?(lang)
          if site.config["verbose"]
            puts "Missing i18n key: #{locale}:#{key}, looking for fallback in #{lang}"
          end
          translation = get_translation(site, lang, key)
        else
          translation = site.parsed_translations[site.config['default_locale']].access(key)
          if site.config["verbose"]
            puts "Missing i18n key: #{locale}:#{key}"
            puts "Using translation '%s' from default locale: %s" %[translation, site.config['default_locale']]
          end
        end
      end
      translation
    end
  end



  ##############################################################################
  # class LocalizeInclude
  #
  # Localization by including whole files that contain the localization text.
  # User must use the "tf" or "translate_file" liquid tags.
  ##############################################################################
  module Tags
    class LocalizeInclude < IncludeTag
    
      #======================================
      # render
      #======================================
      def render(context)
        if       "#{context[@file]}" != "" # Check for page variable
          file = "#{context[@file]}"
        else
          file =            @file
        end
        
        file = Liquid::Template.parse(file).render(context)  # Parses and renders some Liquid syntax on arguments (allows expansions)
        
        site = context.registers[:site] # Jekyll site object
        
        default_locale = site.config['default_locale']

        validate_file_name(file)

        includes_dir = File.join(site.source, '_i18n/' + site.config['locale'])

        # If directory doesn't exist, go to default locale
        if !Dir.exist?(includes_dir)
          includes_dir = File.join(site.source, '_i18n/' + default_locale)
        elsif
          # If file doesn't exist, go to default locale
          Dir.chdir(includes_dir) do
            choices = Dir['**/*'].reject { |x| File.symlink?(x) }
            if !choices.include?(  file)
              includes_dir = File.join(site.source, '_i18n/' + default_locale)
            end
          end
        end
        
        Dir.chdir(includes_dir) do
          choices = Dir['**/*'].reject { |x| File.symlink?(x) }
          
          if choices.include?(  file)
            source  = File.read(file)
            partial = Liquid::Template.parse(source)
            
            context.stack do
              context['include'] = parse_params(  context) if @params
              contents           = partial.render(context)
              ext                = File.extname(file)
              
              converter = site.converters.find { |c| c.matches(ext) }
              contents  = converter.convert(contents) unless converter.nil?
              
              contents
            end
          else
            raise IOError.new "Included file '#{file}' not found in #{includes_dir} directory"
          end
          
        end
      end
    end

    # Override of core Jekyll functionality, to get rid of deprecation
    # warning. See https://github.com/jekyll/jekyll/pull/7117 for more
    # details.
    class PostComparer
      def initialize(name)
        @name = name

        all, @path, @date, @slug = *name.sub(%r!^/!, "").match(MATCHER)
        unless all
          raise Jekyll::Errors::InvalidPostNameError,
                "'#{name}' does not contain valid date and/or title."
        end

        escaped_slug = Regexp.escape(slug)
        @name_regex = %r!_posts/#{path}#{date}-#{escaped_slug}\.[^.]+|
          ^#{path}_posts/?#{date}-#{escaped_slug}\.[^.]+!x
      end
    end
  end



  ##############################################################################
  # class LocalizeLink
  #
  # Creates links or permalinks for translated pages.
  # User must use the "tl" or "translate_link" liquid tags.
  ##############################################################################
  class LocalizeLink < Liquid::Tag

    #======================================
    # initialize
    #======================================
    def initialize(tag_name, key, tokens)
      super
      @key = key
    end

    #======================================
    # render
    #======================================
    def render(context)
      if      "#{context[@key]}" != "" # Check for page variable
        key = "#{context[@key]}"
      else
        key = @key
      end
      
      key = Liquid::Template.parse(key).render(context)  # Parses and renders some Liquid syntax on arguments (allows expansions)
      
      site = context.registers[:site] # Jekyll site object
      
      key               = key.split
      namespace         = key.shift
      locale_param      = key.shift
      strip_locale      = key.shift || false
      translate_url(site, namespace, locale_param, strip_locale)
    end
  end

  module Filters
    module URLFilters
      def sanitized_baseurl
        site = @context.registers[:site]
        baseurl = site.config["baseurl_root"]
        return "" if baseurl.nil?

        baseurl.to_s.chomp("/")
      end
    end
  end
end # End module Jekyll



################################################################################
# class Hash
################################################################################
unless Hash.method_defined? :access
  class Hash
  
    #======================================
    # access
    #======================================
    def access(path)
      ret = self

      begin
        path.split('.').each do |p|

          if p.to_i.to_s == p
            ret = ret[p.to_i]
          else
            ret = ret[p.to_s] || ret[p.to_sym]
          end

          break unless ret
        end
      rescue TypeError => e
        puts("Could not find key '#{path}', aborting. . .")
        raise

      end
      ret
    end
  end
end



################################################################################
# Liquid tags definitions

Liquid::Template.register_tag('t',              Jekyll::LocalizeTag          )
Liquid::Template.register_tag('translate',      Jekyll::LocalizeTag          )
Liquid::Template.register_tag('tf',             Jekyll::Tags::LocalizeInclude)
Liquid::Template.register_tag('translate_file', Jekyll::Tags::LocalizeInclude)
Liquid::Template.register_tag('tl',             Jekyll::LocalizeLink         )
Liquid::Template.register_tag('translate_link', Jekyll::LocalizeLink         )
