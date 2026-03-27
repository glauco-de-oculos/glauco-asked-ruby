Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

PROJECT_ROOT = File.expand_path("../..", __dir__) unless defined?(PROJECT_ROOT)
JARLIBS_DIR = File.join(PROJECT_ROOT, "jarlibs") unless defined?(JARLIBS_DIR)
PUBLIC_DIR = File.join(PROJECT_ROOT, "public") unless defined?(PUBLIC_DIR)
FRAMEWORK_WEB_DIR = File.join(__dir__, "web") unless defined?(FRAMEWORK_WEB_DIR)
NODE_MODULES_DIR = File.join(FRAMEWORK_WEB_DIR, "node_modules") unless defined?(NODE_MODULES_DIR)

require 'java'
require File.join(JARLIBS_DIR, 'swt.jar')

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

require_relative '../llm/GlaucoLLM'

puts "[GlaucoWebshell] 🚀 Definindo classe GlaucoWebshell..."

class ApiRuntime
  def initialize(browser:, display:, host:)
    @browser = browser
    @display = display
    @host = host
  end

  def open_url(url)
    raise "browser nil" unless @browser
    raise "host nil" unless @host

    @host.ensure_ui_alive

    @host.run_ui do
      @browser.setUrl(url)
    end

    "opened #{url}"
  end

  def eval_js(js)
    @host.run_ui { @browser.evaluate(js) }
  end
end


class GUIShell < GlaucoLLM
  attr_reader :shell, :browser, :display
  attr_accessor :state, :visible

  def initialize(visible: false)
    super()

    @visible = visible
    @state = { current_url: nil, last_action: nil, context: {} }

    start_ui_thread if @visible

    puts "[GUIShell] BEFORE setup_llm"

    setup_llm(
      system_config_instructions: File.expand_path("system_config_instructions.md", __dir__),
      domain_specific_knowledge: File.expand_path("dinamicas diretrizes - prompt.md", __dir__)
    )

    puts "[GUIShell] AFTER setup_llm"

    setup_runtime
  end

  # ===========================================================
  # 🔑 NOVO: runtime injection
  # ===========================================================
  def setup_runtime
    ensure_ui_alive

    runtime = ApiRuntime.new(
      browser: @browser,
      display: @display,
      host: self
    )

    # 🔑 apenas injeta runtime
    @agent.instance_variable_set(:@runtime, runtime)

    # 🔑 atualizar lista de métodos
    runtime_methods = runtime.public_methods(false).map(&:to_s)
    @agent.instance_variable_set(:@runtime_methods, runtime_methods)
  end

  # ===========================================================
  # execução
  # ===========================================================
  def interpretar(input_text)
    raise "runtime não configurado" unless @agent.instance_variable_get(:@runtime)

    puts "[Interpreter] input_text: #{input_text.inspect}"

    result = @agent.run(input_text)

    run_ui do
      puts "[UI] browser=#{browser}"
    end

    result
  end

  # ===========================================================
  # UI
  # ===========================================================
  def start_ui_thread
    if defined?(@display) && @display && !@display.isDisposed
      @display.async_exec { @shell.dispose rescue nil }
      sleep 0.5
      @display.dispose rescue nil
    end

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

        while !@shell.disposed?
          @display.sleep unless @display.read_and_dispatch
        end

        @display.dispose rescue nil
      rescue => e
        puts "[UI ERROR] #{e.class} - #{e.message}"
      end
    end

    start = Time.now
    until ready && @browser && !@browser.isDisposed
      sleep 0.05
      raise "Timeout ao iniciar UI" if Time.now - start > 10
    end
  end

  def ensure_ui_alive
    if @ui_thread.nil? || !@ui_thread.alive?
      start_ui_thread
      sleep 0.5
    end

    if @display.nil? || @display.isDisposed
      start_ui_thread
    end
  end

  # ===========================================================
  # execução UI segura
  # ===========================================================
  def run_ui(&block)
    ensure_ui_alive

    if Thread.current == @ui_thread
      block.call
    else
      result = nil

      @display.sync_exec do
        result = block.call
      end

      result
    end
  end

  # ===========================================================
  # helpers
  # ===========================================================
  def evaluate(js)
    run_ui { @browser.evaluate(js) }
  end

  def read_html
    evaluate("return document.documentElement.outerHTML;")
  end
end

module Frontend
  DEBUG = true
  DEFAULT_PORT = (ENV["GLAUCO_PORT"] || "8000").to_i

  def debug_log(msg)
    puts "[DEBUG] #{msg}" if DEBUG
  end

  require 'java'
  require 'set'
  require 'webrick'

  root = PUBLIC_DIR
  node_modules = NODE_MODULES_DIR
  @server_port = DEFAULT_PORT

  WEBrick::HTTPUtils::DefaultMimeTypes['js'] = 'application/javascript'

  def self.port_available?(port)
    TCPServer.new('127.0.0.1', port).close
    true
  rescue Errno::EADDRINUSE, Errno::EACCES
    false
  end

  def self.resolve_server_port(preferred_port = DEFAULT_PORT)
    port = preferred_port.to_i
    50.times do
      return port if port_available?(port)
      port += 1
    end

    raise "Nenhuma porta disponivel encontrada a partir de #{preferred_port}"
  end

  @server_port = resolve_server_port(@server_port)

  server = WEBrick::HTTPServer.new(
    Port: @server_port,
    DocumentRoot: root,
    AccessLog: [],
    Logger: WEBrick::Log.new(nil, 0)
  )

  def self.server_port
    @server_port
  end

  def self.base_url
    "http://localhost:#{@server_port}"
  end

  server.mount('/node_modules', WEBrick::HTTPServlet::FileHandler, node_modules)

  require 'uri'

  server.mount_proc '/files' do |req, res|
    raw_path = req.path.sub('/files/', '')

    # 🔥 decode URL (%20, %C3%8D, etc)
    decoded = URI.decode_www_form_component(raw_path)

    # 🔥 normalizar path windows
    full_path = decoded

    puts "[FILES] raw=#{raw_path}"
    puts "[FILES] decoded=#{decoded}"
    puts "[FILES] full_path=#{full_path}"

    if File.exist?(full_path)
      res.body = File.binread(full_path)
      res['Content-Type'] =
        WEBrick::HTTPUtils.mime_type(full_path, WEBrick::HTTPUtils::DefaultMimeTypes)
    else
      puts "[FILES] NOT FOUND"
      res.status = 404
      res.body = "Not found"
    end
  end

  # ===========================================================
  # 🔥 Carbon Registry
  # ===========================================================
module CarbonRegistry
  require 'json'
  require 'set'

  DEBUG = true

  def self.log(msg)
    puts "[CarbonRegistry] #{msg}" if DEBUG
  end

  @css_src = "/node_modules/@carbon/styles/css/styles.css"
  @js_src  = "/carbon.js"

  HTML_TAGS = Set.new(%w[
    html head body title meta link style script
    div span p a
    form label fieldset legend
    ul ol li
    main section article aside footer
    table thead tbody tr th td
    h1 h2 h3 h4 h5 h6
    br hr
    svg path
  ])

  @available_tags = Set.new
  @map = {}

  class << self
    attr_accessor :css_src, :js_src
    attr_reader :available_tags, :map
  end

  # ===========================================================
  # 🔥 LOAD COM DEBUG TOTAL
  # ===========================================================
  def self.load!
    json_path = File.join(NODE_MODULES_DIR, "@carbon", "web-components", "custom-elements.json")

    log "loading from: #{json_path}"

    unless File.exist?(json_path)
      log "❌ custom-elements.json NOT FOUND"
      return
    end

    data = JSON.parse(File.read(json_path))

    log "json keys: #{data.keys}"

    @available_tags = Set.new
    @map = {}

    tags =
      if data["modules"]
        log "using modules[] format"
        data["modules"].flat_map { |m| m["declarations"] || [] }
          .map { |d| d["tagName"] || d["tag"] }
      elsif data["declarations"]
        log "using declarations[] root format"
        data["declarations"].map { |d| d["tagName"] || d["tag"] }
      elsif data["tags"]
        log "using tags[] format"
        data["tags"].map { |t| t["name"] }
      else
        log "❌ unknown format"
        []
      end

    log "total raw tags: #{tags.size}"

    tags.each do |tag|
      next unless tag
      next unless tag.start_with?("cds-")

      @available_tags << tag

      base = tag.sub(/^cds-/, '').tr('-', '_')
      @map[base] = tag

      log "mapped: #{base} → #{tag}"
    end

    log "✔ total mapped: #{@map.size}"

    if @map.empty?
      log "❌ MAP EMPTY — parsing falhou"
    end
  end

  # ===========================================================
  # 🔥 RESOLVE COM DEBUG
  # ===========================================================
  def self.resolve(ruby_name)
    name = ruby_name.to_s

    log "resolve called: #{name}"

    # HTML
    if HTML_TAGS.include?(name)
      log "→ html tag passthrough"
      return name
    end

    # cds_
    if name.start_with?("cds_")
      tag = name.tr('_', '-')
      if @available_tags.include?(tag)
        log "→ cds direct hit: #{tag}"
        return tag
      else
        log "⚠ cds_ not found in available_tags: #{tag}"
        return name
      end
    end

    # DSL
    if @map[name]
      log "→ mapped: #{@map[name]}"
      return @map[name]
    end

    log "⚠ MISS: #{name}"
    name
  end

  # ===========================================================
  # HTML
  # ===========================================================
  def self.script_tag
    log "injecting script: #{@js_src}"
    %(<script type="module" src="#{@js_src}"></script>)
  end

  def self.style_tag
    log "injecting css: #{@css_src}"
    %(<link rel="stylesheet" href="#{@css_src}">)
  end

  def self.defined_style_tag
    <<~HTML
      <style>
        cds-*:not(:defined) {
          visibility: hidden;
        }
      </style>
    HTML
  end
end

  CarbonRegistry.load!


  # ===========================================================
  # 🔥 Browser callbacks
  # ===========================================================
  $callbacks = {}

  def browserFunctionFac(callback_name)
    Class.new(Java::OrgEclipseSwtBrowser::BrowserFunction) do
      define_method(:function) do |*args|
        begin
          arg = args.first
          arg = arg[0] if arg.is_a?(Java::JavaLang::Object[]) && arg.size == 1
          $callbacks[callback_name].call(arg)
        rescue => e
          puts "Error in callback #{callback_name}: #{e.class} - #{e.message}"
        end
      end
    end.new($browser, callback_name)
  end

  # ===========================================================
  # 🔥 Root Renderer
  # ===========================================================
  class RootRenderer
    attr_accessor :browser, :root_component

    def initialize(browser)
      @browser = browser
    end

    def bind_callback(event, proc_obj)
      callback_name = "callback_#{rand(1000..9999)}"
      $callbacks[callback_name] = proc_obj
      browserFunctionFac(callback_name)

      attr = event.to_s.gsub('_', '')

      if attr == "onclick"
        %(onclick="event.preventDefault(); event.stopPropagation(); #{callback_name}(this.value); return false;")
      else
        %(#{attr}="#{callback_name}(this.value)")
      end
    end

    def render
      puts "[RootRenderer.render] full render" if DEBUG
      return unless @root_component

      body_html = @root_component.render_to_html

      html = <<~HTML
        <!DOCTYPE html>
        <html theme="g100">
          <head>
            <meta charset="UTF-8">
            #{CarbonRegistry.style_tag}
            #{CarbonRegistry.script_tag}
            #{CarbonRegistry.defined_style_tag}
            <style>
              html, body {
                margin: 0;
                padding: 0;
                height: 100%;
              }
            </style>
          </head>
          <body class="cds-theme-zone-g100">
            #{body_html}
          </body>
        </html>
      HTML

      File.write(File.join(PUBLIC_DIR, "index.html"), html)
    end
  end

  # ===========================================================
  # 🔥 Component DSL
  # ===========================================================
  class Component
    attr_accessor :state, :children, :parent_renderer, :attrs

    def initialize(parent_renderer: nil, **attrs)
      puts "initilizing component" if DEBUG
      @state = {}
      @bindings = {}
      @effects = []
      @effect_sequence = 0
      @pending_effect_ids = Set.new
      @active_effect_ids = Set.new
      @effect_batch_depth = 0
      @is_flushing_effects = false
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
      callback_name = "callback_#{$callbacks.length + 1}"
      $callbacks[callback_name] = callback
      browserFunctionFac(callback_name) if @parent_renderer&.browser
      callback_name
    end

    class Symbol
      def >(other)
        sp = StatePath.new(self)
        sp.append_part(other)
      end
    end

    class StatePath
      def initialize(base)
        @parts = [base.to_s]
      end

      def [](key)
        @parts << key.to_s
        self
      end

      def append_part(part)
        @parts << part.to_s
        self
      end

      def to_s
        first, *rest = @parts
        rest.reduce(first) { |acc, part| "#{acc}[#{part}]" }
      end
    end

    def render_binding_result(result)
      case result
      when Array
        result.map { |r| r.respond_to?(:render_to_html) ? r.render_to_html : r.to_s }.join("\n")
      when Component
        result.render_to_html
      else
        result.to_s
      end
    end

    def bind(state_key, node, &block)
      state_path = state_key.is_a?(StatePath) ? state_key : StatePath.new(state_key)
      path_str = state_path.to_s

      node_html = node.to_s
      node_html = node_html.sub(
        /<([a-zA-Z0-9\-_]+)([^>]*)>/,
        '<\1\2 data-bind="' + path_str + '">'
      )

      @bindings[path_str] = { path: state_path, key: path_str, block: block }

      value = dig_state_path(state_path)

      begin
        inner_html = render_binding_result(block.call(value))
      rescue => e
        puts "⚠️ Erro ao executar binding para #{path_str}: #{e.class} - #{e.message}"
        inner_html = ""
      end

      node_html.sub(%r{</[a-zA-Z0-9\-_]+>}, inner_html + '\0')
    end

    def dig_state_path(state_path)
      parts = normalize_state_path(state_path).scan(/([^\[\]]+)/).flatten

      parts.reduce(@state) do |obj, key|
        break nil if obj.nil?

        if obj.is_a?(Array)
          idx = Integer(key, exception: false)
          break nil if idx.nil?
          obj[idx]
        elsif obj.is_a?(Hash)
          key_sym = key.to_sym
          if obj.key?(key_sym)
            obj[key_sym]
          elsif obj.key?(key)
            obj[key]
          else
            nil
          end
        else
          nil
        end
      end
    end

    def effect(deps, immediate: true, run_on_init: true, &block)
      dep_paths = Array(deps).map { |dep| normalize_state_path(dep) }
      raise ArgumentError, "effect precisa de pelo menos uma dependencia" if dep_paths.empty?
      raise ArgumentError, "effect precisa de um bloco" unless block

      @effect_sequence += 1
      effect = {
        id: @effect_sequence,
        deps: dep_paths,
        immediate: immediate,
        block: block
      }

      @effects << effect
      run_effect(effect) if run_on_init
      effect
    end

    def batch(&block)
      @effect_batch_depth += 1
      block.call
    ensure
      @effect_batch_depth -= 1
      flush_pending_effects if @effect_batch_depth.zero?
    end

    def commit(&block)
      return batch(&block) if block_given?

      flush_pending_effects
    end

    def set_state(path, new_value, replace: false)
      path_str = normalize_state_path(path)

      parts = path_str.scan(/([^\[\]]+)/).flatten
      last_key = parts.pop

      target = parts.reduce(@state) do |obj, key|
        key_sym = key.to_sym
        obj[key_sym] ||= {}
        obj[key_sym]
      end

      last_key_sym = last_key.to_sym
      current_value = target[last_key_sym]

      target[last_key_sym] =
        if !replace && current_value.is_a?(Hash) && new_value.is_a?(Hash)
          current_value.merge(new_value)
        else
          new_value
        end

      notify_bindings(path_str)
      schedule_effects(path_str)
      flush_pending_effects if @effect_batch_depth.zero?
    end

    def notify_bindings(path)
      path_str = normalize_state_path(path)
      puts "notify_bindings called for path #{path_str}" if DEBUG

      binding = @bindings[path_str]

      puts binding.inspect

      return path_str unless binding

      puts binding.inspect

      value = dig_state_path(binding[:path])

      puts value.inspect

      begin
        puts "Binding found for #{path_str}, updating DOM with value: #{value.inspect}" if DEBUG
        inner_html = render_binding_result(binding[:block].call(value))
      rescue => e
        puts "⚠️ Erro ao renderizar binding #{path_str}: #{e.class} - #{e.message}"
        inner_html = ""
      end

      js = <<~JS
        (() => {
          const nodes = document.querySelectorAll('[data-bind="#{path_str}"]');
          nodes.forEach(el => {
            el.innerHTML = #{inner_html.to_json};
          });
        })();
      JS

      @parent_renderer&.browser&.execute(js)
      path_str
    end

    private

    def normalize_state_path(path)
      path.is_a?(StatePath) ? path.to_s : path.to_s
    end

    def schedule_effects(changed_path)
      @effects.each do |registered_effect|
        next unless registered_effect[:deps].any? { |dep| related_state_paths?(dep, changed_path) }

        if registered_effect[:immediate]
          run_effect(registered_effect)
        else
          @pending_effect_ids.add(registered_effect[:id])
        end
      end
    end

    def flush_pending_effects
      return if @is_flushing_effects
      return if @pending_effect_ids.empty?

      @is_flushing_effects = true

      loop do
        pending_ids = @pending_effect_ids.to_a
        @pending_effect_ids.clear
        break if pending_ids.empty?

        pending_ids.each do |effect_id|
          registered_effect = @effects.find { |effect| effect[:id] == effect_id }
          run_effect(registered_effect) if registered_effect
        end
      end
    ensure
      @is_flushing_effects = false
    end

    def run_effect(registered_effect)
      return unless registered_effect
      return if @active_effect_ids.include?(registered_effect[:id])

      @active_effect_ids.add(registered_effect[:id])
      values = registered_effect[:deps].map { |dep| dig_state_path(dep) }
      registered_effect[:block].call(*values)
    ensure
      @active_effect_ids.delete(registered_effect[:id]) if registered_effect
    end

    def related_state_paths?(left, right)
      left == right || left.start_with?("#{right}[") || right.start_with?("#{left}[")
    end

    public

    def add_child(comp)
      comp.parent_renderer = parent_renderer
      @children << comp
    end

    def method_missing(method_name, *args, **kwargs, &block)
      name = method_name.to_s
      tag(CarbonRegistry.resolve(name), *args, **kwargs, &block)
    end

    def respond_to_missing?(_method_name, _include_private = false)
      true
    end

    def tag(name, *args, **attrs, &block)
      resolved_name = CarbonRegistry.resolve(name)

      content_or_attrs = args.first

      inner_content =
        if block
          result = instance_eval(&block)
          components = result.is_a?(Array) ? result : [result]

          components.map do |c|
            add_child(c) if c.is_a?(Component)
            c.is_a?(Component) ? c.render_to_html : c.to_s
          end.join
        else
          content_or_attrs.is_a?(Component) ? content_or_attrs.render_to_html : content_or_attrs.to_s
        end

      html_attrs = attrs.map do |k, v|
        attr_name = k.to_s.tr('_', '-')

        if k.to_s.start_with?("on") && v.is_a?(Proc)
          @parent_renderer.bind_callback(k, v)
        elsif v == true
          attr_name
        elsif v == false || v.nil?
          nil
        else
          "#{attr_name}=\"#{v}\""
        end
      end.compact.join(" ")

      if html_attrs.empty?
        "<#{resolved_name}>#{inner_content}</#{resolved_name}>"
      else
        "<#{resolved_name} #{html_attrs}>#{inner_content}</#{resolved_name}>"
      end
    end

    def p(*args, **attrs, &block)
      tag(:p, *args, **attrs, &block)
    end

    def render_to_html
      @children = []
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
      puts "rerenderrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr"
      @parent_renderer.render
    end
  end

  def +(other)
    left = respond_to?(:render_to_html) ? render_to_html : to_s
    right = other.is_a?(Component) ? other.render_to_html : other.to_s
    left + right
  end

  def async(&block)
    $display.async_exec { block.call }
  end


  $display = Display.new
  $shell   = Shell.new($display)
  $shell.setLayout(FillLayout.new)

  $browser = Browser.new($shell, 0)
  $root    = RootRenderer.new($browser)
  
  Thread.new { server.start }

  def self.start!
    $shell.open
    $display.async_exec do
      $browser.setUrl("#{base_url}/index.html")
    end
    run_loop
  end
  
  def run_loop
		while !$shell.disposed?
			$display.sleep unless $display.read_and_dispatch
		end
    $display.dispose
  end

end
