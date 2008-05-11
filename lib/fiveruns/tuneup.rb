require File.dirname(__FILE__) << "/tuneup/step"

module Fiveruns
  module Tuneup
    
    class << self
      
      attr_accessor :collecting
      attr_accessor :running
      
      def run(allow=true)
        @running = allow
        Fiveruns::Tuneup.log :info, "Recording: #{recording?} (collecting: #{@collecting})"
        clear if recording?
        result = yield
        @running = false
        result
      end
      
      def recording?
        @running && @collecting
      end
      
      def data
        @data ||= Fiveruns::Tuneup::RootStep.new
      end
      
      def stack
        @stack ||= [data]
      end
      
      def clear
        @data = @stack = nil
      end
      
      def start
        log :info, "Starting..."
        install_instrumentation
      end
      
      def stopwatch
        start = Time.now.to_f
        yield
        (Time.now.to_f - start) * 1000
      end
      
      def step(name, layer=nil, &block)
        if recording?
          result = nil
          returning ::Fiveruns::Tuneup::Step.new(name, layer, &block) do |s|
            stack.last << s
            stack << s
            s.time = stopwatch { result = yield }
            stack.pop
          end
          result
        else
          yield
        end
      end

      def instrument(target, *mods)
        mods.each do |mod|
          # Change target for 'ClassMethods' module
          real_target = mod.name.demodulize == 'ClassMethods' ? (class << target; self; end) : target
          real_target.__send__(:include, mod)
          # Find all the instrumentation hooks and chain them in
          mod.instance_methods.each do |meth|
            name = meth.to_s.sub('_with_fiveruns_tuneup', '')
            real_target.alias_method_chain(name, :fiveruns_tuneup) rescue nil
          end
        end
      end
      
      def instrumented_adapters
        @instrumented_adapters ||= []
      end
      
      def log(level, text)
        RAILS_DEFAULT_LOGGER.send(level, "FiveRuns TuneUp (v#{Fiveruns::Tuneup::Version::STRING}): #{text}")
      end
      
      #######
      private
      #######

      def install_instrumentation
        instrumentation_path = File.join(File.dirname(__FILE__) << "/tuneup/instrumentation")
        Dir[File.join(instrumentation_path, '/**/*.rb')].each do |filename|
          constant_path = filename[(instrumentation_path.size + 1)..-4]
          constant_name = path_to_constant_name(constant_path)
          if (constant = constant_name.constantize rescue nil)
            instrumentation = "Fiveruns::Tuneup::Instrumentation::#{constant_name}".constantize
            log :info, "Instrumenting #{constant_name}"
            constant.__send__(:include, instrumentation)
          else
            log :debug, "#{constant_name} not found; skipping instrumentation."
          end
        end
      end
      
      def path_to_constant_name(path)
        parts = path.split(File::SEPARATOR)
        parts.map(&:camelize).join('::').sub('Cgi', 'CGI')
      end
      
    end
    
  end
end
  