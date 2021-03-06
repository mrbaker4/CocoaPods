require 'fileutils'

module Pod
  class Command
    class Repo < Command
      self.abstract_command = true

      # @todo should not show a usage banner!
      #
      self.summary = 'Manage spec-repositories'

      class Add < Repo
        self.summary = 'Add a spec repo.'

        self.description = <<-DESC
          Clones `URL` in the local spec-repos directory at `~/.cocoapods`. The
          remote can later be referred to by `NAME`.
        DESC

        self.arguments = 'NAME URL [BRANCH]'

        def initialize(argv)
          @name, @url, @branch = argv.shift_argument, argv.shift_argument, argv.shift_argument
          super
        end

        def validate!
          super
          unless @name && @url
            help! "Adding a repo needs a `NAME` and a `URL`."
          end
        end

        def run
          UI.section("Cloning spec repo `#{@name}` from `#{@url}`#{" (branch `#{@branch}`)" if @branch}") do
            config.repos_dir.mkpath
            Dir.chdir(config.repos_dir) { git!("clone '#{@url}' #{@name}") }
            Dir.chdir(dir) { git!("checkout #{@branch}") } if @branch
            SourcesManager.check_version_information(dir)
          end
        end
      end

      #-----------------------------------------------------------------------#

      class Update < Repo
        self.summary = 'Update a spec repo.'

        self.description = <<-DESC
          Updates the local clone of the spec-repo `NAME`. If `NAME` is omitted
          this will update all spec-repos in `~/.cocoapods`.
        DESC

        self.arguments = '[NAME]'

        def initialize(argv)
          @name = argv.shift_argument
          super
        end

        def run
          SourcesManager.update(@name, true)
        end
      end

      #-----------------------------------------------------------------------#

      class Lint < Repo
        self.summary = 'Validates all specs in a repo.'

        self.description = <<-DESC
          Lints the spec-repo `NAME`. If a directory is provided it is assumed
          to be the root of a repo. Finally, if `NAME` is not provided this
          will lint all the spec-repos known to CocoaPods.
        DESC

        self.arguments = '[ NAME | DIRECTORY ]'

        def self.options
          [["--only-errors", "Lint presents only the errors"]].concat(super)
        end

        def initialize(argv)
          @name = argv.shift_argument
          @only_errors = argv.flag?('only-errors')
          super
        end

        # @todo Part of this logic needs to be ported to cocoapods-core so web
        #       services can validate the repo.
        #
        # @todo add UI.print and enable print statements again.
        #
        def run
          if @name
            dirs = File.exists?(@name) ? [ Pathname.new(@name) ] : [ dir ]
          else
            dirs = config.repos_dir.children.select {|c| c.directory?}
          end
          dirs.each do |dir|
            SourcesManager.check_version_information(dir)
            UI.puts "\nLinting spec repo `#{dir.realpath.basename}`\n".yellow
            podspecs = Pathname.glob( dir + '**/*.podspec')
            invalid_count = 0

            messages_by_type = {}
            podspecs.each do |podspec|
              # print "\033[K -> #{podspec.relative_path_from(dir)}\r" unless config.silent?
              validator = Validator.new(podspec)
              validator.quick       = true
              validator.repo_path   = dir
              validator.only_errors = @only_errors
              validator.disable_ui_output = true

              validator.validate
              invalid_count += 1 if validator.result_type == :error
              unless validator.validated?
                if @only_errors
                  results = validator.results.select { |r| r.type.to_s == "error" }
                else
                  results = validator.results
                end
                sorted_results = results.sort_by { |r| [r.type.to_s, r.message] }
                sorted_results.each do |result|
                  name = validator.spec ? validator.spec.name : podspec.relative_path_from(dir)
                  version = validator.spec ? validator.spec.version : 'unknown'
                  messages_by_type[result.type] ||= {}
                  messages_by_type[result.type][result.message] ||= {}
                  messages_by_type[result.type][result.message][name] ||= []
                  messages_by_type[result.type][result.message][name] << version
                end
              end
            end

            # print "\033[K" unless config.silent?
            messages_by_type.each do |type, names_by_message|
              names_by_message.each do |message, versions_by_names|
                color = type == :error ? :red : :yellow
                UI.puts "[#{type}] #{message}".send(color)
                versions_by_names.each { |name, versions| UI.puts "  - #{name} (#{versions * ', '})" }
                UI.puts
              end
            end

            UI.puts "Analyzed #{podspecs.count} podspecs files.\n\n"

            if invalid_count == 0
              UI.puts "All the specs passed validation.".green << "\n\n"
            else
              raise Informative, "#{invalid_count} podspecs failed validation."
            end
          end
        end
      end

      #-----------------------------------------------------------------------#

      extend Executable
      executable :git

      def dir
        config.repos_dir + @name
      end
    end
  end
end

