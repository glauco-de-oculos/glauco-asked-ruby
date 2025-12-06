Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require 'java'
require './jarlibs/swt.jar'

java_import 'org.eclipse.swt.widgets.Display'
java_import 'org.eclipse.swt.widgets.Shell'
java_import 'org.eclipse.swt.layout.FillLayout'
java_import 'org.eclipse.swt.browser.Browser'
java_import 'org.eclipse.swt.browser.BrowserFunction'
java_import "org.eclipse.swt.browser.LocationAdapter"
java_import 'org.eclipse.swt.widgets.FileDialog'
java_import 'org.eclipse.swt.SWT'
java_import 'java.awt.Toolkit'
java_import 'java.awt.datatransfer.DataFlavor'
java_import 'org.eclipse.swt.dnd.Clipboard'
java_import 'org.eclipse.swt.dnd.TextTransfer'

class WebAction
  attr_reader :result, :done
  
  def initialize
      @done = false
      @result = nil
      @callbacks = []
  end
  
  def then(&block)
      if @done
      block.call(@result)
      else
      @callbacks << block
      end
      self
  end
  
  def resolve(value)
      @done = true
      @result = value
      @callbacks.each { |cb| cb.call(value) }
  end
  
  def wait_load(timeout: 30)
      start = Time.now
      until @done || (Time.now - start) > timeout
      sleep 0.05
      end
      @result
  end
end

require_relative '../glauco/glauco-framework.rb'

puts "[GlaucoWebshell] 🚀 Definindo classe GlaucoWebshell..."
# api_automacoes.rb
unless defined?(ApiAutomacoes)
  module ApiAutomacoes
    # Módulo placeholder para evitar erro de referência
  end
end

class GlaucoGUIShell < GlaucoPlastic
  puts "[GlaucoWebshell] 🚀 Definindo método initialize..."
  attr_reader :shell, :browser, :display # Para acesso de leitura (objetos UI)
  attr_accessor :state, :visible # Para acesso de leitura/escrita (@state e @visible)
  
  def initialize(visible: false, api_automacoes: File.expand_path("api_automacoes.rb", __dir__))
    if api_automacoes && !api_automacoes.empty?
      require_relative api_automacoes
    end

    require 'ruby_llm'
    @state = { current_url: nil, last_action: nil, context: {} }
    @lmstudio_ready = false

    start_ui_thread if @visible
    start_lmstudio
    setup_llm
  end

  def setup_llm
    @chat = super(system_config_instructions: File.expand_path("system_config_instructions.md",  __dir__), domain_specific_knowledge: File.expand_path('dinamicas diretrizes - prompt.md', __dir__))

    puts "super setup_llm:#{@chat}"

    carregar_api_de_automacoes
  end
  
  def carregar_api_de_automacoes
    begin 
      tool_classes = ApiAutomacoes.constants.map do |const_name|
      tool_class = ApiAutomacoes.const_get(const_name)
        if tool_class.is_a?(Class) && tool_class.ancestors.include?(RubyLLM::Tool)
          # 🔑 PASSO CRÍTICO: Inicialize a ferramenta passando a instância do agente (self)
          tool_class.new(agente_host: self) 
        end
      end.compact

      @chat.with_tools(*tool_classes)
      true
    rescue
      puts "Falhou"
      false
    end
  end

  public
  def interpretar(input_text)
    case input_text
    when "carregar base de conhecimento"
      carregar_base_de_conhecimento 
    when "carregar api de automações"
      carregar_api_de_automacoes
    
    else
      puts "[Interpreter] input_text: #{input_text.inspect}"
      
      wait_for_http_ready(SERVER_PORT)
      
      result = ""
      run_ui do 
        puts "@browser #{browser}"
        @chat.ask(super(input_text)) { |chunk| result << chunk.content.to_s }
      end
      #puts "[Interpreter] Resposta bruta do LLM:\n#{result}"

      result
    end
  end

  def start_ui_thread
    if defined?(@display) && @display && !@display.isDisposed
      puts "[UI] ⚠️ Display ainda ativo, descartando antes de recriar..."
      @display.async_exec { @shell.dispose rescue nil }
      sleep 0.5
      @display.dispose rescue nil
    end

    puts "[UI] 🚀 Criando nova thread de UI..."

    ready = false

    @ui_thread = Thread.new do
      begin
        @display = Display.new
        @shell   = Shell.new(@display)
        @shell.setLayout(FillLayout.new)
        @browser = Browser.new(@shell, 0)
        @shell.setText("Agente de Automação")
        @shell.setSize(1024, 768)
        @shell.open

        ready = true
        puts "[UI] 🧠 Thread de UI iniciada (#{Thread.current.object_id})"

        while !@shell.disposed?
          @display.sleep unless @display.read_and_dispatch
        end

        puts "[UI] 💥 Loop gráfico finalizado. Encerrando display..."
        @display.dispose rescue nil
      rescue => e
        puts "[UI] ❌ Erro crítico no loop de UI: #{e.class} - #{e.message}"
      end
    end

    # espera a UI estar de pé
    start = Time.now
    until ready && @browser && !@browser.isDisposed
      sleep 0.05
      raise "Timeout ao iniciar UI" if Time.now - start > 10
    end
  end

  def ensure_ui_alive
    if @ui_thread.nil? || !@ui_thread.alive?
        puts "[UI] 🧩 Thread de UI encerrada — reiniciando..."
        start_ui_thread
        sleep 0.5 # pequeno atraso para garantir criação do Display
    end
  
    if @display.nil? || @display.isDisposed
        puts "[UI] 🧩 Display inválido — reiniciando..."
        start_ui_thread
    end
  end

# Automation
  def read_html
    run_async do
      @browser.evaluate("return document.documentElement.outerHTML;")
    end
  end

  def evaluate(js, label = nil)
    run_ui { 
      result = @browser.evaluate(js)
      # puts "[#{label} - Evaluate]: #{result}"
      result
    }
  end

  def run_async(&block)
    if @display.nil? || @display.isDisposed
      puts "[run_async] ⚠️ Display inexistente — recriando..."
      @display = Display.new
    end

    if Display.get_current
      block.call
    else
      @display.async_exec(&block)
      @display.wake
    end
  end


  def run_ui(&block)
  
    puts "[UI] 🚀 Executando bloco no thread de UI... #{block.inspect}"
    ensure_ui_alive

    if Thread.current == @ui_thread
      # já estamos no thread de UI
      block.call
    else
      # executa o bloco dentro do thread da UI
      
      # 🔑 PASSO 1: Captura explícita do bloco (referência forte contra GC).
      ui_block = block 
      
      result = nil
      
      puts "[UI] 🧠 Enviando bloco para execução no thread de UI..."
      
      # 🔑 PASSO 2 CRÍTICO: Uso de sync_exec (e não async_exec).
      # Isso BLOQUEIA o thread chamador (onde está o `open_url`) até que
      # o thread da UI termine a execução do bloco, garantindo que `ui_block`
      # esteja no escopo e não seja liberado.
      @display.sync_exec do 
        begin
          # Use a variável local capturada.
          puts "[UI] 🚀 Bloco recebido no thread de UI, executando... #{ui_block.class.inspect}"
          
          # Agora a chamada é segura.
          result = ui_block.call
          
        rescue => e
          puts "[UI] ❌ Erro ao executar no thread de UI: #{e.class} - #{e.message}"
          raise e 
        end
      end
      
      return result
    end
  end
  
end

module Frontend
  $callbacks = {}
  def browserFunctionFac(callback_name)
    Class.new(Java::OrgEclipseSwtBrowser::BrowserFunction) do
      define_method(:function) do |*args|
        begin
          arg = args.first
          arg = arg[0] if arg.is_a?(Java::JavaLang::Object[]) && arg.size == 1
          puts "#{callback_name} called with #{arg.inspect}"
          $callbacks[callback_name].call(arg)
        rescue => e
          puts "Error in callback #{callback_name}: #{e.class} - #{e.message}"
        end
      end
    end.new($browser, callback_name)
  end

  def getClipBoardText
    java.awt.Toolkit.getDefaultToolkit.getspawnClipboard.getData(
      java.awt.datatransfer.DataFlavor.stringFlavor
    )
  end

  class RootRenderer
    attr_accessor :browser, :callbacks, :root_component

    def initialize(browser)
      @browser = browser
    end
    
    def bind_callback(event, proc_obj)
      callback_name = "callback_#{rand(1000..9999)}"
      $callbacks[callback_name] = proc_obj
      if @browser
        browserFunctionFac(callback_name)
      end

      # Retorna o atributo HTML correto
      "#{event.to_s.gsub('_', '')}=\"#{callback_name}(this.value)\""
    end
    def render
      puts "calling render"
      return unless @root_component
      puts "passed root_component condition"
      puts "now will call browser.set_text"
      @browser.set_text(@root_component.render_to_html)
    end

    def update_dom(placeholder_id, new_html)
      # garanta string
      html_str = new_html.is_a?(String) ? new_html : Array(new_html).join
      puts "updated dom #{placeholder_id}"
      puts "html_str: #{html_str}"
      js = <<~JS
        (function(){
          var el = document.getElementById("#{placeholder_id}");
          if (el) {
            el.innerHTML = #{html_str.to_json};
          }
        })();
      JS
      @browser.evaluate(js)
    end
  end

  class Component
    attr_accessor :state, :children, :parent_renderer, :attrs

    def initialize(parent_renderer: nil, **attrs)
      puts "initilizing component"
      @state = {}
      @bindings = []
      @children = []
      @parent_renderer = parent_renderer
      @event_listeners = {}
      @attrs = self.class.default_attrs.merge(attrs)
    end

    undef select
    undef p

    class << self
      def attrs(defaults = {})
        @default_attrs = defaults
        self
      end

      def default_attrs
        @default_attrs || {}
      end
    end

    def add_event_listener(event_name, &callback)
      callback_name = "callback_#{$callbacks.length+1}"
      $callbacks[callback_name] = callback
      if @parent_renderer&.browser
        browserFunctionFac(callback_name)
      end
    end
    
    # Define o método _ que inicializa um StatePath a partir de Symbol
    class Symbol
      def >(other)
        sp = StatePath.new(self)
        sp.append_part(other)
      end
    end

    # Classe StatePath
    class StatePath
      def initialize(base)
        @parts = [base.to_s]
      end

      def [](key)
        @parts << key.to_s
        self
      end

      def to_s
        first, *rest = @parts
        rest.reduce(first) { |acc, part| "#{acc}[#{part}]" }
      end
    end

    # --- Bindings avançados ---
    def bind(state_key, node, &block)
      # garante que sempre temos um StatePath
      puts "binding #{state_key} to node #{node}"
      state_path = state_key.is_a?(StatePath) ? state_key : StatePath.new(state_key)

      path_str = state_path.to_s
      puts "path_str: #{path_str}"

      # injeta data-bind no HTML
      node = node.sub(/<(\w+)([^>]*)>/, "<\\1\\2 data-bind=\"#{path_str}\">")
      # puts "node after data-bind injection: #{node}"

      # registra o binding
      @bindings << { path: state_path, key: path_str, block: block }
      puts "registered bindings: #{@bindings}"

      # busca valor atual
      value = dig_state_path(state_path)
      puts "current value for #{path_str}: #{value.inspect}"

      begin
        puts "current value for #{path_str}: #{value.inspect}"
        result = block.call(value)

        inner_html =
          case result
          when Array
            result.map { |r| r.is_a?(Component) ? r.render_to_html : r.to_s }.join
          when Component
            result.render_to_html
          else
            result.to_s
          end
      rescue => e
        puts "⚠️ Erro ao executar binding para #{path_str}: #{e.class} - #{e.message}"
        inner_html = ""
      end

      # puts "inner_html: #{inner_html}"
      node = node.sub(%r{</\w+>}, inner_html + '\0')
      puts "node after inner_html injection: #{node}"

      node
    end

    def dig_state_path(state_path)
      puts "dig_state_path called with #{state_path}"
      parts = state_path.to_s.scan(/([^\[\]]+)/).flatten
      parts.reduce(@state) do |obj, key|
        break nil if obj.nil?

        if obj.is_a?(Array)
          puts "Accessing array with key #{key}"
          idx = key.to_i rescue nil
          break nil if idx.nil?
          obj[idx]
        elsif obj.is_a?(Hash)
          puts "Accessing hash with key #{key}"
          key_sym = key.to_sym
          if obj.key?(key_sym)
            puts "Found key #{key_sym} in hash"
            obj[key_sym]
          elsif obj.key?(key)
            puts "Found key #{key} in hash"
            obj[key]
          else
            nil
          end
        else
          nil
        end
      end
    end

    # --- Atualização de estado com paths complexos ---
    def set_state(path, new_value)
      path_str = path.is_a?(StatePath) ? path.to_s : path.to_s
      puts "set_state called with path #{path_str} and value #{new_value.inspect}"

      parts = path_str.split(/[:\[\]]/).reject(&:empty?)
      last_key = parts.pop
      target = parts.reduce(@state) do |obj, key|
        if obj[key.to_sym].nil?
          obj[key.to_sym] = {}
        end
        obj[key.to_sym]
      end

      target[last_key.to_sym] = new_value

      notify_bindings(path)
    end

    # --- Notificação de bindings ---
    def notify_bindings(path)
      path_str = path.is_a?(StatePath) ? path.to_s : path.to_s
      puts "notify_bindings called for path #{path_str}"

      @bindings.each do |binding|
        binding_path_str = binding[:path].to_s

        # verifica se binding é afetado: match exato ou prefixo
        if path_str == binding_path_str || binding_path_str.start_with?("#{path_str}:") || binding_path_str.start_with?("#{path_str}[")
          value = dig_state_path(binding[:path])
          puts "Binding found for #{binding_path_str}, updating DOM with value: #{value.inspect}"

          begin
            puts "Calling binding block for #{binding_path_str} with value #{value.inspect}"
            result = binding[:block].call(value)
            puts "Binding block result for #{binding_path_str}: #{result.to_s}"

            # Garante que sempre teremos string
            inner_html =
              case result
              when Array
                result.map { |r| r.is_a?(Component) ? r.render_to_html : r.to_s }.join
              when Component
                result.render_to_html
              else
                result.to_s
              end
          rescue => e
            puts "⚠️ Erro ao renderizar binding #{binding_path_str}: #{e.class} - #{e.message}"
            inner_html = ""
          end

          # puts "Generated inner_html for #{binding_path_str}: #{inner_html.inspect}"

          js = <<~JS
            (() => {
              const el = document.querySelector('[data-bind="#{binding_path_str}"]');
              if (el) el.innerHTML = #{inner_html.to_json};
            })();
          JS

          res = @parent_renderer.browser.execute(js)

          puts "DOM updated for binding #{binding_path_str}"
        end
      end
      path_str
    end

    public
    def add_child(comp)
      comp.parent_renderer = self.parent_renderer
      puts "comp.inspect: #{comp.inspect}"
      @children << comp
    end

    def method_missing(method_name, *args, **kwargs, &block)
      tag(method_name, *args, **kwargs, &block)
    end

    def respond_to_missing?(method_name, include_private = false)
      true
    end

    def tag(name, *args, **attrs, &block)
      puts "tag called with name #{name}, args #{args.inspect}, attrs #{attrs.inspect}"
      content_or_attrs = args.first

      inner_content = if block
        result = instance_eval(&block)

        # Normaliza para array
        components = result.is_a?(Array) ? result : [result]

        # Adiciona cada filho e renderiza
        components.map do |c|
          add_child(c) if c.is_a?(Component)
          c.is_a?(Component) ? c.render_to_html : c.to_s
        end.join
      else
        content_or_attrs.is_a?(Component ) ? content_or_attrs.render_to_html : content_or_attrs.to_s
      end

      html_attrs = attrs.map do |k, v|
        if k.to_s.start_with?("on") && v.is_a?(Proc)
          @parent_renderer.bind_callback(k, v)
        else
          "#{k}=\"#{v}\""
        end
      end.join(" ")

      @event_listeners.each do |event, proc_obj|
        html_attrs += " #{add_event_listener(event, &proc_obj)}"
      end

      @attrs.each do |k, v|
        html_attrs += "#{k}=\"#{v}\""
      end

      res = "<#{name} #{html_attrs}>#{inner_content}</#{name}>"

      # puts "Generated HTML for tag #{name}: #{res}"
      res
    end

    def p(*args, **attrs, &block)
      tag(:p, *args, **attrs, &block)
    end

    def render_to_html
      return "" unless @render_block
      instance_eval(&@render_block).to_s
    end


    def ui(&block)
      @render_block = block
    end

    def define_render(&block)
      @render_block = block
    end

    def render
      instance_eval(&@render_block)
    end

    def run_js(js_code)
      @parent_renderer.browser.evaluate(js_code)
    end

    def rerender
      puts "called"
      @parent_renderer.render
    end
  end

  def +(other)
    self.render_to_html + (other.is_a?(Component) ? other.render_to_html : other.to_s)
  end

  $display = Display.new
  $shell = Shell.new($display)
  $shell.setLayout(FillLayout.new)
  $browser = Browser.new($shell, 0)
  $root = Frontend::RootRenderer.new($browser)

  def async(&block)
    $display.async_exec do
      block.call
    end
  end

  at_exit do
    # Event loop
    while !$shell.disposed?
      $display.sleep unless $display.read_and_dispatch
    end
    $display.dispose  
  end
end