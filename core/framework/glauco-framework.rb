Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

PROJECT_ROOT = File.expand_path("../..", __dir__) unless defined?(PROJECT_ROOT)
JARLIBS_DIR = File.join(PROJECT_ROOT, "jarlibs") unless defined?(JARLIBS_DIR)
PUBLIC_DIR = File.join(PROJECT_ROOT, "public") unless defined?(PUBLIC_DIR)
FRAMEWORK_WEB_DIR = File.join(__dir__, "web") unless defined?(FRAMEWORK_WEB_DIR)
NODE_MODULES_DIR = File.join(FRAMEWORK_WEB_DIR, "node_modules") unless defined?(NODE_MODULES_DIR)

require 'java'
require 'fileutils'
require 'json'
require 'net/http'
require 'open3'
require 'ruby_llm'
require 'shellwords'
require 'timeout'
require 'uri'
require File.join(JARLIBS_DIR, 'swt.jar')

java_import 'org.eclipse.swt.widgets.Display'
java_import 'org.eclipse.swt.widgets.Shell'
java_import 'org.eclipse.swt.widgets.Composite'
java_import 'org.eclipse.swt.widgets.Listener'
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

class GlaucoBasicPlasticAgent
  raw_ollama_host = ENV.fetch("OLLAMA_HOST", "http://127.0.0.1:11434").sub(%r{/*$}, "")
  DEFAULT_OPENAI_COMPAT_ENDPOINT = raw_ollama_host.sub(%r{/v1$}, "") + "/v1"
  DEFAULT_MODEL_NAME = ENV.fetch("OLLAMA_MODEL", "gemma4:e2b")
  DEFAULT_LLAMA_SERVER_HOST = ENV.fetch("GLAUCO_LLAMASERVER_HOST", "127.0.0.1")
  DEFAULT_LLAMA_SERVER_PORT = ENV.fetch("GLAUCO_LLAMASERVER_PORT", "1234").to_i
  DEFAULT_LLAMA_SERVER_ENDPOINT = ENV.fetch("GLAUCO_LLAMASERVER_ENDPOINT", "http://#{DEFAULT_LLAMA_SERVER_HOST}:#{DEFAULT_LLAMA_SERVER_PORT}/v1")
  DEFAULT_LLAMA_SERVER_MODEL_KEY = ENV.fetch("GLAUCO_LLAMASERVER_MODEL_KEY", "https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF")
  FRAMEWORK_MODELS_DIR = File.join(__dir__, "models")
  FRAMEWORK_LLAMA_SERVER_MODEL_PATH = ENV.fetch("GLAUCO_LLAMASERVER_LOCAL_MODEL_PATH", File.join(FRAMEWORK_MODELS_DIR, "gemma-4-e2b-it.gguf"))
  LMS_BIN_DIR = File.join(Dir.home, ".lmstudio", "bin")
  LLAMA_SERVER_BIN = ENV.fetch("GLAUCO_LLAMASERVER_BIN", "llama-server")
  LLAMA_SERVER_LOG = File.join(Dir.home, ".lmstudio", "logs", "glauco-llama-server.log")

  SYSTEM = <<~SYS
    #You are an RLM agent.

    ##STRICT RULES:
    - ALWAYS use ```repl``` blocks
    - NEVER answer directly outside ```repl```
    - NEVER wrap code in `puts`, `print`, `p`, strings, or explanations
    - NEVER output code as text that still needs to be copied and run
    - ONLY use Ruby
    - You MUST set variables you use
    - You can use multiple steps, but the FINAL step must set the variable `answer`

    ##Execution model:
    - You have access to:
      1) Variables → persistent state
      2) Runtime methods → callable functions

    - Call runtime methods like normal Ruby functions:
      open_url("https://...")

    - Variables are already defined, do not redeclare unless needed


    ##TERMINATION PROTOCOL (CRITICAL):
    - When you have the final result, you MUST:
      1) Assign it to a variable named `answer`
      2) Output a single ```repl``` block that sets `answer`
      3) Do NOTHING after that
  SYS
  # ---------------------------
  # TEST SUITE
  # ---------------------------
  module TestSuite

    TestCase = Struct.new(
      :name, :input, :initial_vars, :expect, :verify_with_llm,
      keyword_init: true
    )

    class Runner
      DEFAULT_TEST_MODEL = ENV.fetch("OLLAMA_MODEL", DEFAULT_MODEL_NAME)

      attr_reader :cases, :results

      def initialize(agent:, model: DEFAULT_TEST_MODEL, cases: [])
        @agent = agent
        @endpoint = agent.endpoint
        @model = model
        @cases = cases
        @results = []

        puts "initilized"
      end

      def add(tc)
        @cases << tc
      end

      def run!
        puts "run!"

        configure_rubyllm!

        @cases.each do |tc|
          puts "\n=== #{tc.name} ==="

          @agent.reset!
          @agent.vars.delete("answer")

          tc.initial_vars&.each do |k,v|
            @agent.vars[k.to_s] = v
          end

          puts "[INPUT] #{tc.input}"

          output = @agent.run(tc.input)

          passed =
            if tc.verify_with_llm
              verify_with_llm(tc, output)
            else
              compare(tc.expect, output)
            end

          puts "[OUTPUT] #{output}"
          puts "[PASS?] #{passed}"

          @results << {
            name: tc.name,
            passed: passed,
            output: output
          }
        end

        summary
      end

      private

      # ---------------------------
      # CONFIG GLOBAL CONTROLADO
      # ---------------------------
      def configure_rubyllm!
        RubyLLM.configure do |c|
          c.openai_api_base = @endpoint
          c.openai_api_key  = "local"
          c.openai_use_system_role = true
        end
      end

      # ---------------------------
      # COMPARAÇÃO
      # ---------------------------
      def compare(expect, out)
        return expect.call(out) if expect.respond_to?(:call)
        expect.to_s.strip == out.to_s.strip
      end

      # ---------------------------
      # VERIFIER (STATELESS CHAT)
      # ---------------------------
      def verify_with_llm(tc, output)
        configure_rubyllm!
        chat = RubyLLM.chat(
          model: @model,
          provider: :openai,
          assume_model_exists: true
        )

        res = chat.ask(<<~PROMPT)
          You are a strict evaluator.

          Task:
          #{tc.input}

          Expected:
          #{tc.expect}

          Output:
          #{output}

          Return ONLY:
          PASS or FAIL
        PROMPT

        res.content.to_s.strip == "PASS"
      end

      # ---------------------------
      # SUMMARY
      # ---------------------------
      def summary
        total = @results.size
        ok = @results.count { |r| r[:passed] }

        puts "\nSUMMARY: #{ok}/#{total}"
      end
    end

    def self.case(**args)
      TestCase.new(**args)
    end
  end
  attr_reader :vars, :history, :endpoint

  DEFAULT_ENDPOINT = DEFAULT_OPENAI_COMPAT_ENDPOINT
  DEFAULT_MODEL    = DEFAULT_MODEL_NAME

  def initialize(
    endpoint: DEFAULT_ENDPOINT,
    model: DEFAULT_MODEL,
    llm_provider: ENV.fetch("GLAUCO_LLM_PROVIDER", nil),
    llama_server_model_key: ENV.fetch("GLAUCO_LLAMASERVER_MODEL_KEY", DEFAULT_LLAMA_SERVER_MODEL_KEY),
    llama_server_identifier: ENV.fetch("GLAUCO_LLAMASERVER_IDENTIFIER", nil),
    llama_server_model_path: ENV.fetch("GLAUCO_LLAMASERVER_MODEL_PATH", nil),
    llama_server_gpu: ENV.fetch("GLAUCO_LLAMASERVER_GPU", nil),
    llama_server_context_length: ENV.fetch("GLAUCO_LLAMASERVER_CONTEXT_LENGTH", nil),
    llama_server_ttl: ENV.fetch("GLAUCO_LLAMASERVER_TTL", nil)
  )
    puts "[Glauco] 🚀 Inicializando Glauco Framework (RLM core)..."

    @model = model
    @endpoint = endpoint
    @llm_provider = normalize_llm_provider(llm_provider, endpoint)
    @llama_server_model_key = presence(llama_server_model_key) || DEFAULT_LLAMA_SERVER_MODEL_KEY
    @llama_server_identifier = presence(llama_server_identifier) || @llama_server_model_key
    @llama_server_model_path = presence(llama_server_model_path) || FRAMEWORK_LLAMA_SERVER_MODEL_PATH
    @llama_server_gpu = presence(llama_server_gpu)
    @llama_server_context_length = integer_or_nil(llama_server_context_length)
    @llama_server_ttl = integer_or_nil(llama_server_ttl)
    @initial_vars = {}
    @vars = {}
    @history = []
    @runtime = nil
    @runtime_methods = []
    @last_code = nil
    @config_path = nil
    @domain_specific_knowledge = nil

    initialize_llm_backend!
  end

  def build_agent(initial_vars: {}, runtime: nil)
    reconfigure_agent!(
      initial_vars: initial_vars,
      runtime: runtime
    )
  end

  def attach_runtime(runtime)
    @runtime =
      if runtime.is_a?(Module)
        Object.new.extend(runtime)
      else
        runtime
      end

    @runtime_methods =
      if @runtime
        @runtime.public_methods(false).map(&:to_s)
      else
        []
      end

    runtime
  end

  # ===========================================================
  # execução
  # ===========================================================
  def interpretar(input_text)
    raise "LLM não inicializado. Chame build_agent primeiro." if @runtime.nil? && @initial_vars.empty?

    run(input_text)
  end

  def run(input, max_iter: 8)
    vars.delete("answer")
    @last_code = nil

    max_iter.times do
      if vars.key?("answer")
        puts "[AGENT] 🛑 answer already exists, stopping loop"
        return vars["answer"]
      end
      puts "[AGENT] step..."

      chat = build_chat
      res = chat.ask(build_prompt(input))

      text = clean_utf8(res.content)
      puts "\n[LLM]\n#{text}"

      codes = extract_repl(text)
      puts "[NO REPL FOUND]" if codes.empty?

      codes.each do |code|
        puts "\n[REPL]\n#{code}"

        if code == @last_code
          puts "[AGENT] ⚠️ repeated code, stopping"
          return vars["answer"] if vars.key?("answer")
          return "Repeated code without final answer"
        end

        @last_code = code

        out, _ = execute(code)
        out = clean_utf8(out)

        puts "[RESULT] #{out}"

        if vars.key?("answer")
          puts "[AGENT] ✅ final answer detected, stopping"
          return vars["answer"]
        end
      end

      history << msg(:assistant, text)
    end

    "No final answer"
  end

  def build_chat
    RubyLLM.configure do |c|
      c.openai_api_base = @endpoint
      c.openai_api_key  = "local"
      c.openai_use_system_role = true
    end

    RubyLLM.chat(
      model: @model,
      provider: :openai,
      assume_model_exists: true
    )
  end

  # ===========================================================
  # extras
  # ===========================================================
  def reset!
    @vars = @initial_vars.dup
    @history.clear

    puts @vars, @history
  end

  def test_runner(cases: [])
    TestSuite::Runner.new(
      agent: self,
      model: @model,
      cases: cases
    )
  end

  def bootstrap_agent!(system_config_instructions:, domain_specific_knowledge: nil, runtime: nil, capability_schema: nil, extra_vars: {})
    puts "[LLM] 🚀 bootstrap_agent! (framework bootstrap)"

    @config_path = File.expand_path(system_config_instructions)
    @domain_specific_knowledge = domain_specific_knowledge && File.expand_path(domain_specific_knowledge)

    initial_vars = load_bootstrap_vars(
      config_path: @config_path,
      knowledge_path: @domain_specific_knowledge,
      capability_schema: capability_schema,
      extra_vars: extra_vars
    )

    build_agent(initial_vars: initial_vars, runtime: runtime)
  end

  def bind_runtime_capabilities!(runtime, capability_schema: nil)
    attach_runtime(runtime)

    if capability_schema
      vars["capability_schema"] =
        capability_schema.is_a?(String) ? capability_schema : JSON.pretty_generate(capability_schema)
    end

    runtime
  end

  def execute(code)
    ctx = @runtime
    raise "runtime not configured" unless ctx

    vars.each do |k, v|
      ctx.instance_variable_set("@#{k}", v)
    end

    result = ctx.instance_eval(code)
    vars["answer"] = result unless result.nil?

    [result, vars.keys]
  rescue => e
    puts "[EXEC ERROR] #{e.class} - #{e.message}"
    puts e.backtrace.first(10)
    ["ERROR: #{e.class} - #{e.message}", []]
  end

  def build_prompt(input)
    vars_block =
      if vars.empty?
        "None"
      else
        vars.keys.join(", ")
      end

    runtime_block =
      if @runtime_methods.empty?
        "None"
      else
        @runtime_methods.join(", ")
      end

    [
      msg(:system, SYSTEM),
      msg(:system, <<~CTX),
        Runtime methods (functions you can call directly in Ruby):
        #{runtime_block}

        Variables (persistent state, read/write):
        #{vars_block}
      CTX
      *history,
      msg(:user, "Task: #{input}\nNext step:")
    ]
  end

  def tool_call?(res)
    res.respond_to?(:tool_calls) && res.tool_calls && !res.tool_calls.empty?
  end

  def handle_tool_calls(res)
    res.tool_calls.each do |call|
      name = call["name"]
      args = call["arguments"] || {}

      tool = @tools.find { |t| t.name == name }

      if tool.nil?
        puts "[TOOL] not found: #{name}"
        next
      end

      puts "[TOOL] calling #{name} with #{args}"

      result = tool.execute(**args.transform_keys(&:to_sym))

      puts "[TOOL RESULT] #{result}"

      history << {
        role: "tool",
        name: name,
        content: result.to_s
      }
    end
  rescue => e
    puts "[TOOL ERROR] #{e.message}"
  end

  private

  def initialize_llm_backend!
    return unless @llm_provider == "llama-server"

    initialize_llama_server!
  end

  def initialize_llama_server!
    ensure_lms_installed!
    ensure_llama_server_binary!
    ensure_llama_server_model_downloaded!
    restart_llama_server! if llama_server_running? && !llama_server_matches_target?
    ensure_llama_server_http!
    wait_for_llama_server_models!

    @endpoint = DEFAULT_LLAMA_SERVER_ENDPOINT
    @model = @llama_server_identifier if presence(@llama_server_identifier)
  end

  def ensure_lms_installed!
    return if File.executable?(File.join(LMS_BIN_DIR, "lms")) || command_available?("lms")

    raise "LM Studio CLI não encontrado. Instale pelo script oficial: curl -fsSL https://lmstudio.ai/install.sh | bash"
  end

  def ensure_llama_server_binary!
    return if command_available?(LLAMA_SERVER_BIN)

    raise "llama-server não encontrado. Defina GLAUCO_LLAMASERVER_BIN ou instale llama.cpp com o binário llama-server."
  end

  def ensure_llama_server_model_downloaded!
    sync_framework_model_from_download! if framework_model_outdated?
    return if resolved_llama_server_model_path

    model_key = presence(@llama_server_model_key)
    raise "Defina GLAUCO_LLAMASERVER_MODEL_KEY para baixar um modelo GGUF via LM Studio." unless model_key

    download_llama_server_model!(model_key)
    sync_framework_model_from_download!
    return if resolved_llama_server_model_path

    raise "O modelo #{model_key} não foi localizado depois do download via LM Studio."
  end

  def ensure_llama_server_http!
    return if llama_server_running?

    model_path = resolved_llama_server_model_path
    raise "Nenhum caminho de modelo GGUF disponível para o llama-server." unless model_path

    FileUtils.mkdir_p(File.dirname(LLAMA_SERVER_LOG))

    args = [
      LLAMA_SERVER_BIN,
      "--model", model_path,
      "--host", DEFAULT_LLAMA_SERVER_HOST,
      "--port", DEFAULT_LLAMA_SERVER_PORT.to_s,
      "--alias", @llama_server_identifier.to_s
    ]
    args += ["--ctx-size", @llama_server_context_length.to_s] if @llama_server_context_length
    args += ["--gpu-layers", llama_server_gpu_layers] if @llama_server_gpu
    args += ["--timeout", @llama_server_ttl.to_s] if @llama_server_ttl

    pid = spawn(
      args.first,
      *args.drop(1),
      in: "/dev/null",
      out: LLAMA_SERVER_LOG,
      err: LLAMA_SERVER_LOG,
      pgroup: true
    )
    Process.detach(pid)

    wait_until!("llama-server não iniciou em #{DEFAULT_LLAMA_SERVER_ENDPOINT}", timeout: 30) do
      llama_server_running?
    end
  end

  def wait_for_llama_server_models!
    wait_until!("llama-server subiu, mas o endpoint /v1/models não ficou pronto.", timeout: 30) do
      uri = URI("#{DEFAULT_LLAMA_SERVER_ENDPOINT}/models")
      response = Net::HTTP.get_response(uri)
      response.is_a?(Net::HTTPSuccess)
    rescue StandardError
      false
    end
  end

  def llama_server_running?
    uri = URI("#{DEFAULT_LLAMA_SERVER_ENDPOINT}/models")
    response = Net::HTTP.get_response(uri)
    response.is_a?(Net::HTTPSuccess)
  rescue StandardError
    false
  end

  def llama_server_matches_target?
    uri = URI("#{DEFAULT_LLAMA_SERVER_ENDPOINT}/models")
    response = Net::HTTP.get_response(uri)
    return false unless response.is_a?(Net::HTTPSuccess)

    payload = JSON.parse(response.body)
    models = Array(payload["data"]) + Array(payload["models"])
    identifiers = models.flat_map do |entry|
      [entry["id"], entry["model"], entry["name"], *Array(entry["aliases"])].compact
    end

    identifiers.map!(&:to_s)
    identifiers.include?(@llama_server_identifier.to_s)
  rescue StandardError
    false
  end

  def restart_llama_server!
    system("pkill", "-f", "#{LLAMA_SERVER_BIN} --model")
    wait_until!("llama-server antigo não encerrou.", timeout: 10) do
      !llama_server_running?
    end
  rescue StandardError
    nil
  end

  def resolved_llama_server_model_path
    return @llama_server_model_path if @llama_server_model_path && File.exist?(@llama_server_model_path)

    nil
  end

  def locate_downloaded_llama_server_model_path
    models_root = discover_lmstudio_models_root
    return nil unless models_root && Dir.exist?(models_root)

    search_terms = llama_server_search_terms
    candidates = Dir.glob(File.join(models_root, "**", "*.gguf"))
      .reject { |path| File.basename(path).downcase.include?("mmproj") }
      .select do |path|
        haystack = path.downcase
        search_terms.any? { |term| haystack.include?(term) }
      end

    candidates.min_by { |path| File.size(path) }
  end

  def run_lms!(*args)
    run_lms(*args, allow_failure: false)
  end

  def run_lms(*args, allow_failure:)
    stdout, stderr, status = Open3.capture3(lms_env, "lms", *args)
    return stdout if status.success?
    return stdout if allow_failure

    command = (["lms"] + args).shelljoin
    details = [stdout, stderr].reject(&:empty?).join("\n").strip
    raise "Falha ao executar #{command}: #{details}"
  end

  def lms_env
    {
      "PATH" => [LMS_BIN_DIR, ENV["PATH"]].compact.join(":")
    }
  end

  def command_available?(name)
    system({ "PATH" => [LMS_BIN_DIR, ENV["PATH"]].compact.join(":") }, "bash", "-lc", "command -v #{Shellwords.escape(name)} >/dev/null 2>&1")
  end

  def wait_until!(message, timeout:)
    Timeout.timeout(timeout) do
      loop do
        return true if yield
        sleep 1
      end
    end
  rescue Timeout::Error
    raise message
  end

  def normalize_llm_provider(provider, endpoint)
    chosen = presence(provider)
    return chosen if chosen
    return "llama-server" if endpoint.to_s.start_with?(DEFAULT_LLAMA_SERVER_ENDPOINT)

    nil
  end

  def download_llama_server_model!(model_key)
    run_lms("get", model_key, "--gguf", "-y", allow_failure: false)
  rescue StandardError => first_error
    fallback_url = huggingface_url_for(model_key)
    raise first_error unless fallback_url

    run_lms!("get", fallback_url, "--gguf", "-y")
  end

  def huggingface_url_for(model_key)
    key = model_key.to_s.strip
    return nil if key.empty?
    return nil if key.match?(%r{\Ahttps?://}i)
    return nil unless key.include?("/")

    "https://huggingface.co/#{key}"
  end

  def discover_lmstudio_models_root
    explicit = ENV["LMSTUDIO_MODELS_DIR"].to_s.strip
    return explicit unless explicit.empty?

    default_root = File.join(Dir.home, ".lmstudio", "models")
    return default_root if Dir.exist?(default_root)

    candidates = Dir.glob(File.join(Dir.home, ".lmstudio", "**", "model-cache"))
    return candidates.first if candidates.any?

    settings_path = File.join(Dir.home, ".lmstudio", "settings.json")
    return nil unless File.exist?(settings_path)

    settings = JSON.parse(File.read(settings_path, encoding: "UTF-8"))
    presence(settings["downloadedModelsPath"]) || presence(settings["modelsPath"])
  rescue JSON::ParserError
    nil
  end

  def framework_model_outdated?
    return false unless @llama_server_model_path && File.exist?(@llama_server_model_path)

    downloaded = locate_downloaded_llama_server_model_path
    return false unless downloaded && File.exist?(downloaded)

    File.size(@llama_server_model_path) != File.size(downloaded)
  end

  def sync_framework_model_from_download!
    source_model_path = locate_downloaded_llama_server_model_path
    return unless source_model_path && File.exist?(source_model_path)

    FileUtils.mkdir_p(File.dirname(@llama_server_model_path))
    FileUtils.cp(source_model_path, @llama_server_model_path)
  end

  def llama_server_search_terms
    key = @llama_server_model_key.to_s.strip
    return [] if key.empty?

    stripped = key.sub(%r{\Ahttps?://huggingface\.co/}i, "").sub(%r{\Ahttps?://}, "")
    candidates = [
      key,
      stripped,
      File.basename(stripped),
      stripped.split("/").last
    ]

    candidates
      .map { |value| value.to_s.downcase.strip }
      .reject(&:empty?)
      .uniq
  end

  def llama_server_gpu_layers
    return "999" if @llama_server_gpu == "max"
    return "0" if @llama_server_gpu == "off"

    ratio = @llama_server_gpu.to_f
    return "0" if ratio <= 0

    [[(ratio * 100).round, 1].max, 999].min.to_s
  end

  def presence(value)
    string = value.to_s.strip
    return nil if string.empty?

    string
  end

  def integer_or_nil(value)
    return nil if value.nil? || value.to_s.strip.empty?

    value.to_i
  end

  def reconfigure_agent!(initial_vars:, runtime:)
    normalized_vars = initial_vars.transform_keys(&:to_s)

    attach_runtime(runtime)

    @initial_vars = normalized_vars
    @vars = @initial_vars.dup
    @history = []
    @last_code = nil

    self
  end

  def msg(role, content)
    { role: role, content: clean_utf8(content) }
  end

  def extract_repl(text)
    text.scan(/```(?:repl|ruby)\n(.*?)```/m)
      .flatten
      .map { |code| normalize_generated_code(code) }
      .reject(&:empty?)
  end

  def clean_utf8(s)
    s.to_s.dup.force_encoding("UTF-8")
      .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
  end

  def normalize_generated_code(code)
    normalized = code.to_s.strip

    if normalized.match?(/\A(?:puts|print|p)\s+/)
      extracted = unwrap_stringified_code(normalized)
      normalized = extracted if extracted
    end

    normalized
  end

  def unwrap_stringified_code(code)
    match = code.match(/\A(?:puts|print|p)\s+(.+)\z/m)
    return nil unless match

    literal = match[1].strip
    return nil unless literal.start_with?('"', "'")

    begin
      unwrapped = eval(literal)
    rescue StandardError
      return nil
    end

    unwrapped.to_s.strip
  end

  def load_bootstrap_vars(config_path:, knowledge_path:, capability_schema:, extra_vars:)
    initial_vars = {}

    unless File.exist?(config_path)
      raise "system_config_instructions não encontrado: #{config_path}"
    end

    initial_vars["system_config"] = File.read(config_path, encoding: "UTF-8")

    if knowledge_path && File.exist?(knowledge_path)
      initial_vars["domain_knowledge"] = File.read(knowledge_path, encoding: "UTF-8")
    end

    if capability_schema
      initial_vars["capability_schema"] =
        capability_schema.is_a?(String) ? capability_schema : JSON.pretty_generate(capability_schema)
    end

    extra_vars.each do |key, value|
      initial_vars[key.to_s] = value
    end

    initial_vars
  end
end

class GlaucoAgentBrowserEnv < GlaucoBasicPlasticAgent
  FRAME_LIMITATION_NOTE = "Frames internos via SWT Browser dependem da engine embutida e de same-origin. O schema abaixo prepara introspeccao e avaliacao em frame quando acessivel."

  def self.capability(name, description, params: [])
    {
      name: name,
      description: description,
      params: params
    }
  end

  def self.capability_schema_definition
    {
      shell: {
        description: "Capacidades do shell SWT para navegacao, DOM e exploracao de frames.",
        frame_support: {
          status: "experimental",
          notes: FRAME_LIMITATION_NOTE,
          fallback_paths: [
            "Migrar a camada de shell para Julia + WebViews quando embutir frames for requisito de primeira linha.",
            "Explorar Tauri + Leptos para manter avaliacao de JavaScript e rotas desktop com melhor controle de webview."
          ]
        },
        capabilities: [
          capability("open_url", "Abre uma URL no browser principal.", params: %w[url]),
          capability("current_url", "Retorna a URL atual do browser principal."),
          capability("eval_js", "Executa JavaScript no documento principal.", params: %w[js]),
          capability("read_html", "Le o HTML renderizado da janela atual."),
          capability("list_frames", "Inspeciona frames acessiveis da janela atual."),
          capability("eval_js_in_frame", "Executa JavaScript em um frame acessivel por indice ou nome.", params: %w[frame_ref js]),
          capability("frame_support_report", "Resume limites atuais de frames internos no SWT Browser.")
        ]
      }
    }
  end

  attr_reader :shell, :browser, :display, :overlay_shell, :overlay_browser
  attr_accessor :state, :visible

  def initialize(visible: false)
    super()

    @visible = visible
    @state = {
      current_url: nil,
      last_action: nil,
      context: {},
      capability_schema: self.class.capability_schema_definition,
      overlay: {
        visible: false,
        requested_visible: false,
        url: nil,
        alpha: 255,
        bounds: nil
      }
    }

    start_ui_thread if @visible

    puts "[GlaucoAgentBrowserEnv] BEFORE bootstrap_agent!"

    bootstrap_agent!(
      system_config_instructions: File.expand_path("system_config_instructions.md", __dir__),
      domain_specific_knowledge: File.expand_path("dinamicas diretrizes - prompt.md", __dir__),
      runtime: self,
      capability_schema: capability_schema
    )

    puts "[GlaucoAgentBrowserEnv] AFTER bootstrap_agent!"
  end

  # ===========================================================
  # execução
  # ===========================================================
  def interpretar(input_text)
    raise "runtime não configurado" unless @runtime

    puts "[Interpreter] input_text: #{input_text.inspect}"

    result = run(input_text)

    run_ui do
      puts "[UI] browser=#{browser}"
    end

    result
  end

  # ===========================================================
  # UI
  # ===========================================================
  def start_ui_thread
    ready = false
    startup_error = nil

    release_frontend_display_if_idle!
    shutdown_ui_thread if @ui_thread&.alive?

    @ui_thread = Thread.new do
      begin
        @display = Display.new
        @shell   = Shell.new(@display)
        @shell.setLayout(FillLayout.new)
        @browser = Browser.new(@shell, 0)
        install_overlay_tracking!

        @shell.setText("Agente de Automação")
        @shell.setSize(1024, 768)
        @shell.open

        ready = true

        while !@shell.disposed?
          @display.sleep unless @display.read_and_dispatch
        end

        @display.dispose rescue nil
      rescue => e
        startup_error = e
        puts "[UI ERROR] #{e.class} - #{e.message}"
      ensure
        ready = true
      end
    end

    start = Time.now
    until ready
      sleep 0.05
      raise "Timeout ao iniciar UI" if Time.now - start > 10
    end

    raise startup_error if startup_error

    start = Time.now
    until @browser && !@browser.isDisposed
      sleep 0.05
      raise "Timeout ao materializar Browser" if Time.now - start > 10
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

  def shutdown_ui_thread
    return unless @ui_thread&.alive?

    begin
      if @display && !@display.isDisposed
        @display.sync_exec do
          @overlay_shell.dispose if @overlay_shell && !@overlay_shell.isDisposed
          @shell.dispose if @shell && !@shell.isDisposed
        end
      end
    rescue StandardError
      # Segue para o cleanup abaixo.
    end

    @ui_thread.join(2)

    @display = nil
    @shell = nil
    @browser = nil
    @overlay_shell = nil
    @overlay_browser = nil
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
    ensure_ui_alive
    raise "browser nil" unless @browser

    run_ui { @browser.evaluate(js) }
  end

  def read_html(*)
    evaluate("return document.documentElement.outerHTML;")
  end

  def open_url(url)
    if !@visible && (@ui_thread.nil? || !@ui_thread.alive?)
      @state[:current_url] = url
      @state[:last_action] = "open_url_external"
      system("xdg-open", url)
      return "opened #{url} externally"
    end

    ensure_ui_alive
    raise "browser nil" unless @browser

    run_ui do
      @state[:current_url] = url
      @state[:last_action] = "open_url"
      @browser.setUrl(url)
    end

    "opened #{url}"
  end

  def current_url(*)
    @state[:current_url].to_s
  end

  def eval_js(js)
    @state[:last_action] = "eval_js"
    if !@visible && (@ui_thread.nil? || !@ui_thread.alive?)
      raise "browser nil: eval_js requer browser embutido. Inicialize com visible: true."
    end

    ensure_ui_alive
    raise "browser nil" unless @browser

    run_ui { @browser.evaluate(js) }
  end

  def list_frames(*)
    raw = eval_js(<<~JS)
      return JSON.stringify((function() {
        const frames = [];
        for (let index = 0; index < window.frames.length; index += 1) {
          const frame = window.frames[index];
          try {
            frames.push({
              index,
              name: frame.name || null,
              location: frame.location ? frame.location.href : null,
              accessible: true
            });
          } catch (error) {
            frames.push({
              index,
              name: null,
              location: null,
              accessible: false,
              error: String(error)
            });
          }
        }

        return {
          count: window.frames.length,
          frames
        };
      })());
    JS

    JSON.parse(raw.to_s)
  rescue JSON::ParserError
    { "count" => 0, "frames" => [], "raw" => raw.to_s }
  end

  def eval_js_in_frame(frame_ref, js)
    escaped_frame = frame_ref.to_s.dump
    escaped_js = js.to_s.dump

    raw = eval_js(<<~JS)
      return JSON.stringify((function() {
        const ref = #{escaped_frame};
        const code = #{escaped_js};
        let target = null;

        if (/^\\d+$/.test(ref)) {
          target = window.frames[Number(ref)];
        } else {
          target = window.frames[ref];
        }

        if (!target) {
          return { ok: false, error: "frame not found", ref };
        }

        try {
          const result = target.eval(code);
          return { ok: true, ref, result };
        } catch (error) {
          return { ok: false, ref, error: String(error) };
        }
      })());
    JS

    JSON.parse(raw.to_s)
  rescue JSON::ParserError
    { "ok" => false, "ref" => frame_ref.to_s, "error" => raw.to_s }
  end

  def frame_support_report(*)
    FRAME_LIMITATION_NOTE
  end

  def capability_schema(*)
    @state[:capability_schema]
  end

  # ===========================================================
  # overlay page
  # ===========================================================
  def overlay_open?
    !!(@overlay_shell && !@overlay_shell.isDisposed && @overlay_shell.getVisible)
  end

  def overlay_page(url: nil, html: nil, bounds: nil, alpha: 255, focus: false)
    show_overlay_page(
      url: url,
      html: html,
      bounds: bounds,
      alpha: alpha,
      focus: focus
    )
  end

  def show_overlay_page(url: nil, html: nil, bounds: nil, alpha: 255, focus: false)
    run_ui do
      ensure_overlay_shell!

      @state[:overlay][:url] = url if url
      @state[:overlay][:alpha] = alpha
      @state[:overlay][:bounds] = bounds if bounds

      begin
        @overlay_shell.setAlpha(alpha)
      rescue StandardError
        # Algumas plataformas/WM nao suportam alpha em Shell.
      end

      sync_overlay_page_bounds(bounds)

      @overlay_browser.setUrl(url) if url
      @overlay_browser.setText(html) if html

      @overlay_shell.setVisible(true)
      @overlay_shell.open
      @overlay_shell.setActive if focus

      @state[:overlay][:visible] = true
      @state[:overlay][:requested_visible] = true
      true
    end
  end

  def hide_overlay_page
    run_ui do
      return unless @overlay_shell && !@overlay_shell.isDisposed

      @overlay_shell.setVisible(false)
      @state[:overlay][:visible] = false
      @state[:overlay][:requested_visible] = false
      true
    end
  end

  def close_overlay_page
    hide_overlay_page
  end

  def dispose_overlay_page
    run_ui do
      return unless @overlay_shell && !@overlay_shell.isDisposed

      @overlay_browser.dispose if @overlay_browser && !@overlay_browser.isDisposed
      @overlay_shell.dispose
      @overlay_browser = nil
      @overlay_shell = nil
      @state[:overlay][:visible] = false
      @state[:overlay][:requested_visible] = false
      true
    end
  end

  def sync_overlay_page_bounds(bounds = nil)
    return unless @browser && !@browser.isDisposed
    return unless @overlay_shell && !@overlay_shell.isDisposed

    browser_bounds = @browser.getBounds
    resolved = resolve_overlay_bounds(browser_bounds, bounds || @state.dig(:overlay, :bounds))
    origin = @browser.toDisplay(resolved[:x], resolved[:y])

    @overlay_shell.setBounds(origin.x, origin.y, resolved[:width], resolved[:height])
    resolved
  end

  def overlay_support_report
    <<~TXT.strip
      SWT overlay page viavel via child Shell + Browser secundario.
      Melhor caminho: Shell filha com SWT::NO_TRIM | SWT::ON_TOP | SWT::TOOL, sincronizada com o Browser principal.
      Limite importante: nao e uma subview real dentro do Browser; e uma janela nativa separada posicionada sobre ele.
      Em Linux/Wayland e em algumas engines do SWT Browser, alpha e coordenadas podem variar por window manager.
    TXT
  end

  private

  def ensure_overlay_shell!
    return @overlay_shell if @overlay_shell && !@overlay_shell.isDisposed

    overlay_style = SWT::NO_TRIM | SWT::ON_TOP | SWT::TOOL
    @overlay_shell = Shell.new(@shell, overlay_style)
    @overlay_shell.setLayout(FillLayout.new)
    @overlay_browser = Browser.new(@overlay_shell, 0)
    @overlay_shell.setVisible(false)

    begin
      @overlay_shell.setAlpha(@state.dig(:overlay, :alpha) || 255)
    rescue StandardError
      # Alpha nao e garantido em todas as plataformas.
    end

    sync_overlay_page_bounds
    @overlay_shell
  end

  def install_overlay_tracking!
    listener = Listener.impl { |_event| sync_overlay_page_bounds if overlay_open? rescue nil }
    deactivate_listener = Listener.impl { |_event| hide_overlay_for_parent_state! rescue nil }
    activate_listener = Listener.impl { |_event| restore_overlay_for_parent_state! rescue nil }
    close_listener = Listener.impl { |_event| dispose_overlay_page rescue nil }

    @shell.addListener(SWT::Move, listener)
    @shell.addListener(SWT::Resize, listener)
    @shell.addListener(SWT::Deactivate, deactivate_listener)
    @shell.addListener(SWT::Iconify, deactivate_listener)
    @shell.addListener(SWT::Activate, activate_listener)
    @shell.addListener(SWT::Deiconify, activate_listener)
    @shell.addListener(SWT::Close, close_listener)
  end

  def resolve_overlay_bounds(browser_bounds, requested_bounds)
    bounds = requested_bounds || {}

    x =
      if bounds.key?(:x)
        bounds[:x].to_i
      else
        (browser_bounds.width * (bounds.fetch(:x_ratio, 0.0))).to_i
      end

    y =
      if bounds.key?(:y)
        bounds[:y].to_i
      else
        (browser_bounds.height * (bounds.fetch(:y_ratio, 0.15))).to_i
      end

    width =
      if bounds.key?(:width)
        bounds[:width].to_i
      else
        (browser_bounds.width * (bounds.fetch(:width_ratio, 1.0))).to_i
      end

    height =
      if bounds.key?(:height)
        bounds[:height].to_i
      else
        (browser_bounds.height * (bounds.fetch(:height_ratio, 0.70))).to_i
      end

    {
      x: x,
      y: y,
      width: [width, 1].max,
      height: [height, 1].max
    }
  end

  def hide_overlay_for_parent_state!
    return unless @overlay_shell && !@overlay_shell.isDisposed
    return unless @state.dig(:overlay, :requested_visible)

    @overlay_shell.setVisible(false)
    @state[:overlay][:visible] = false
  end

  def restore_overlay_for_parent_state!
    return unless @overlay_shell && !@overlay_shell.isDisposed
    return unless @state.dig(:overlay, :requested_visible)

    sync_overlay_page_bounds
    @overlay_shell.setVisible(true)
    @state[:overlay][:visible] = true
  end

  def release_frontend_display_if_idle!
    return unless defined?($display) && $display && !$display.isDisposed

    shell_visible =
      begin
        defined?($shell) && $shell && !$shell.isDisposed && $shell.getVisible
      rescue StandardError
        false
      end

    return if shell_visible

    begin
      $browser.dispose if defined?($browser) && $browser && !$browser.isDisposed
      $shell.dispose if defined?($shell) && $shell && !$shell.isDisposed
      $display.dispose unless $display.isDisposed
    rescue StandardError
      # Se o frontend global nao puder ser reciclado, o startup do shell dedicado
      # ainda vai falhar explicitamente ao tentar abrir outro Display.
    ensure
      if defined?($embedded_surfaces) && $embedded_surfaces
        $embedded_surfaces.each_value do |surface|
          surface.dispose if surface && !surface.isDisposed rescue nil
        end
      end
      $embedded_surfaces = {}
      $browser = nil
      $surface_parent = nil
      $shell = nil
      $display = nil
      $root = nil
    end
  end
end

module Frontend
  DEBUG = true
  DEFAULT_PORT = (ENV["GLAUCO_PORT"] || "8000").to_i
  @overlay_registry = {}
  @embedded_browser_registry = {}

  def debug_log(msg)
    puts "[DEBUG] #{msg}" if DEBUG
  end

  def self.overlay_registry
    @overlay_registry ||= {}
  end

  def self.embedded_browser_registry
    @embedded_browser_registry ||= {}
  end

  def self.register_overlay_page(id, config)
    overlay_registry[id.to_s] = config
  end

  def self.register_embedded_browser(id, config)
    embedded_browser_registry[id.to_s] = config
  end

  def self.register_overlay_geometry_callback(browser, element_id)
    callback_name = "overlay_geom_#{element_id}_#{rand(1000..9999)}"

    $callbacks[callback_name] = proc do |payload|
      begin
        data = payload.is_a?(String) ? JSON.parse(payload) : payload
        update_overlay_geometry(data)
      rescue => e
        puts "[Overlay] geometry callback error: #{e.class} - #{e.message}"
      end
    end

    browserFunctionFac(browser, callback_name)
    callback_name
  end

  def self.register_embedded_browser_geometry_callback(browser, element_id)
    callback_name = "embedded_geom_#{element_id}_#{rand(1000..9999)}"

    $callbacks[callback_name] = proc do |payload|
      begin
        data = payload.is_a?(String) ? JSON.parse(payload) : payload
        update_embedded_browser_geometry(data)
      rescue => e
        puts "[EmbeddedBrowser] geometry callback error: #{e.class} - #{e.message}"
      end
    end

    browserFunctionFac(browser, callback_name)
    callback_name
  end

  def self.update_overlay_geometry(data)
    element_id = data["id"].to_s
    config = overlay_registry[element_id]
    return unless config

    config[:visual_bounds] = {
      x: data["x"].to_i,
      y: data["y"].to_i,
      width: data["width"].to_i,
      height: data["height"].to_i
    }

    if $overlay_state && $overlay_state[:element_id] == element_id && $overlay_state[:requested_visible]
      sync_overlay_page_bounds(config[:visual_bounds])
    end
  end

  def self.update_embedded_browser_geometry(data)
    element_id = data["id"].to_s
    config = embedded_browser_registry[element_id]
    return unless config

    config[:visual_bounds] = {
      x: data["x"].to_i,
      y: data["y"].to_i,
      width: data["width"].to_i,
      height: data["height"].to_i
    }

    sync_embedded_browser_surface(element_id)
  end

  def self.overlay_bridge_script
    <<~HTML
      <script>
        (() => {
          const previous = new Map();

          const collect = () => {
            document.querySelectorAll('[data-overlay-host="true"]').forEach((node) => {
              const callbackName = node.getAttribute('data-overlay-geometry-callback');
              if (!callbackName || typeof window[callbackName] !== 'function') return;

              const rect = node.getBoundingClientRect();
              const payload = {
                id: node.id,
                x: Math.round(rect.left),
                y: Math.round(rect.top),
                width: Math.round(rect.width),
                height: Math.round(rect.height)
              };

              const key = JSON.stringify(payload);
              if (previous.get(node.id) === key) return;

              previous.set(node.id, key);
              window[callbackName](key);
            });
          };

          window.addEventListener('load', collect);
          window.addEventListener('resize', collect);
          window.addEventListener('scroll', collect, true);

          if (typeof ResizeObserver !== 'undefined') {
            const observer = new ResizeObserver(() => collect());
            window.addEventListener('load', () => {
              document.querySelectorAll('[data-overlay-host="true"]').forEach((node) => observer.observe(node));
            });
          }

          setInterval(collect, 250);
        })();
      </script>
    HTML
  end

  def self.embedded_browser_bridge_script
    <<~HTML
      <script>
        (() => {
          const previous = new Map();

          const collect = () => {
            document.querySelectorAll('[data-embedded-browser-host="true"]').forEach((node) => {
              const callbackName = node.getAttribute('data-embedded-browser-geometry-callback');
              if (!callbackName || typeof window[callbackName] !== 'function') return;

              const rect = node.getBoundingClientRect();
              const payload = {
                id: node.id,
                x: Math.round(rect.left),
                y: Math.round(rect.top),
                width: Math.round(rect.width),
                height: Math.round(rect.height)
              };

              const key = JSON.stringify(payload);
              if (previous.get(node.id) === key) return;

              previous.set(node.id, key);
              window[callbackName](key);
            });
          };

          window.addEventListener('load', collect);
          window.addEventListener('resize', collect);
          window.addEventListener('scroll', collect, true);

          if (typeof ResizeObserver !== 'undefined') {
            const observer = new ResizeObserver(() => collect());
            window.addEventListener('load', () => {
              document.querySelectorAll('[data-embedded-browser-host="true"]').forEach((node) => observer.observe(node));
            });
          }

          setInterval(collect, 250);
        })();
      </script>
    HTML
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

  def self.ensure_overlay_shell!
    return $overlay_shell if defined?($overlay_shell) && $overlay_shell && !$overlay_shell.isDisposed

    overlay_style = SWT::NO_TRIM | SWT::ON_TOP | SWT::TOOL
    $overlay_shell = Shell.new($shell, overlay_style)
    $overlay_shell.setLayout(FillLayout.new)
    $overlay_browser = Browser.new($overlay_shell, 0)
    $overlay_shell.setVisible(false)

    begin
      $overlay_shell.setAlpha(255)
    rescue StandardError
      # Alpha depende do window manager.
    end

    install_overlay_tracking!
    $overlay_shell
  end

  def self.install_overlay_tracking!
    return if defined?($overlay_tracking_installed) && $overlay_tracking_installed

    listener = Listener.impl { |_event| sync_overlay_page_bounds if overlay_open? rescue nil }
    deactivate_listener = Listener.impl { |_event| hide_overlay_for_parent_state! rescue nil }
    activate_listener = Listener.impl { |_event| restore_overlay_for_parent_state! rescue nil }
    close_listener = Listener.impl { |_event| dispose_overlay_page rescue nil }

    $shell.addListener(SWT::Move, listener)
    $shell.addListener(SWT::Resize, listener)
    $shell.addListener(SWT::Deactivate, deactivate_listener)
    $shell.addListener(SWT::Iconify, deactivate_listener)
    $shell.addListener(SWT::Activate, activate_listener)
    $shell.addListener(SWT::Deiconify, activate_listener)
    $shell.addListener(SWT::Close, close_listener)

    $overlay_tracking_installed = true
  end

  def self.overlay_open?
    !!(defined?($overlay_shell) && $overlay_shell && !$overlay_shell.isDisposed && $overlay_shell.getVisible)
  end

  def self.show_overlay_page(url: nil, html: nil, bounds: nil, alpha: 255, focus: false)
    ensure_overlay_shell!

    puts "[Overlay] show_overlay_page url=#{url.inspect} html?=#{!html.nil?} bounds=#{bounds.inspect} alpha=#{alpha}"

    begin
      $overlay_shell.setAlpha(alpha)
    rescue StandardError
      # Alpha depende do window manager.
    end

    $overlay_state = {
      url: url,
      html: html,
      alpha: alpha,
      bounds: bounds,
      requested_visible: true
    }

    sync_overlay_page_bounds(bounds)
    $overlay_browser.setText(html) if html
    $overlay_browser.setUrl(url) if url && html.nil?
    $overlay_shell.setVisible(true)
    $overlay_shell.open
    $overlay_shell.setActive if focus
    true
  end

  def self.hide_overlay_page
    return unless defined?($overlay_shell) && $overlay_shell && !$overlay_shell.isDisposed

    $overlay_shell.setVisible(false)
    $overlay_state[:requested_visible] = false if $overlay_state
    true
  end

  def self.close_overlay_page
    hide_overlay_page
  end

  def self.dispose_overlay_page
    return unless defined?($overlay_shell) && $overlay_shell && !$overlay_shell.isDisposed

    $overlay_browser.dispose if defined?($overlay_browser) && $overlay_browser && !$overlay_browser.isDisposed
    $overlay_shell.dispose
    $overlay_browser = nil
    $overlay_shell = nil
    $overlay_state = nil
    true
  end

  def self.sync_overlay_page_bounds(bounds = nil)
    return unless defined?($browser) && $browser && !$browser.isDisposed
    return unless defined?($overlay_shell) && $overlay_shell && !$overlay_shell.isDisposed

    browser_bounds = $browser.getBounds
    resolved = resolve_overlay_bounds(browser_bounds, bounds || ($overlay_state && $overlay_state[:bounds]))
    origin = $browser.toDisplay(resolved[:x], resolved[:y])
    $overlay_shell.setBounds(origin.x, origin.y, resolved[:width], resolved[:height])
    resolved
  end

  def self.resolve_overlay_bounds(browser_bounds, requested_bounds)
    bounds = requested_bounds || {}

    x = bounds.key?(:x) ? bounds[:x].to_i : (browser_bounds.width * bounds.fetch(:x_ratio, 0.0)).to_i
    y = bounds.key?(:y) ? bounds[:y].to_i : (browser_bounds.height * bounds.fetch(:y_ratio, 0.15)).to_i
    width = bounds.key?(:width) ? bounds[:width].to_i : (browser_bounds.width * bounds.fetch(:width_ratio, 1.0)).to_i
    height = bounds.key?(:height) ? bounds[:height].to_i : (browser_bounds.height * bounds.fetch(:height_ratio, 0.70)).to_i

    {
      x: x,
      y: y,
      width: [width, 1].max,
      height: [height, 1].max
    }
  end

  def self.hide_overlay_for_parent_state!
    return unless defined?($overlay_shell) && $overlay_shell && !$overlay_shell.isDisposed
    return unless $overlay_state && $overlay_state[:requested_visible]

    $overlay_shell.setVisible(false)
  end

  def self.restore_overlay_for_parent_state!
    return unless defined?($overlay_shell) && $overlay_shell && !$overlay_shell.isDisposed
    return unless $overlay_state && $overlay_state[:requested_visible]

    sync_overlay_page_bounds
    $overlay_shell.setVisible(true)
  end

  def self.open_overlay_page_for_element(element_id)
    config = overlay_registry[element_id.to_s]
    raise "overlay element not found: #{element_id}" unless config

    bounds = (config[:visual_bounds] || config[:bounds] || {}).dup

    show_overlay_page(
      url: config[:url],
      html: config[:html],
      alpha: (config[:alpha] || 255).to_i,
      bounds: bounds
    )

    $overlay_state[:element_id] = element_id.to_s if $overlay_state

    true
  end

  def self.ensure_embedded_browser_surface!(element_id)
    config = embedded_browser_registry[element_id.to_s]
    raise "embedded browser element not found: #{element_id}" unless config
    raise "surface parent composite não inicializado" unless defined?($surface_parent) && $surface_parent && !$surface_parent.isDisposed

    $embedded_surfaces ||= {}
    surface = $embedded_surfaces[element_id.to_s]
    return surface if surface && !surface.isDisposed

    surface = Browser.new($surface_parent, 0)
    surface.setVisible(false)
    surface.moveAbove(nil)
    $embedded_surfaces[element_id.to_s] = surface
    surface
  end

  def self.show_embedded_browser(element_id)
    config = embedded_browser_registry[element_id.to_s]
    return unless config

    surface = ensure_embedded_browser_surface!(element_id)
    bounds = config[:visual_bounds] || config[:bounds] || {}
    sync_embedded_browser_surface(element_id, bounds)

    if config[:html]
      surface.setText(config[:html])
    elsif config[:url]
      surface.setUrl(config[:url])
    end

    surface.setVisible(config.fetch(:visible, true))
    surface.moveAbove(nil)
    true
  end

  def self.hide_embedded_browser(element_id)
    return unless defined?($embedded_surfaces) && $embedded_surfaces

    surface = $embedded_surfaces[element_id.to_s]
    return unless surface && !surface.isDisposed

    surface.setVisible(false)
    true
  end

  def self.dispose_embedded_browser(element_id)
    return unless defined?($embedded_surfaces) && $embedded_surfaces

    surface = $embedded_surfaces.delete(element_id.to_s)
    return unless surface && !surface.isDisposed

    surface.dispose
    true
  end

  def self.sync_embedded_browser_surface(element_id, fallback_bounds = nil)
    config = embedded_browser_registry[element_id.to_s]
    return unless config

    if config.fetch(:visible, true)
      surface = ensure_embedded_browser_surface!(element_id)
      host_bounds = config[:visual_bounds] || fallback_bounds || config[:bounds]
      return unless host_bounds

      resolved = resolve_embedded_browser_bounds(host_bounds)
      surface.setBounds(resolved[:x], resolved[:y], resolved[:width], resolved[:height])
      surface.setVisible(true)
      surface.moveAbove(nil)
    else
      hide_embedded_browser(element_id)
    end

    true
  end

  def self.sync_embedded_browser_surfaces
    embedded_browser_registry.keys.each do |element_id|
      sync_embedded_browser_surface(element_id)
    end
  end

  def self.resolve_embedded_browser_bounds(bounds)
    {
      x: bounds[:x].to_i,
      y: bounds[:y].to_i,
      width: [bounds[:width].to_i, 1].max,
      height: [bounds[:height].to_i, 1].max
    }
  end

  def self.sync_frontend_layout!
    return unless defined?($surface_parent) && $surface_parent && !$surface_parent.isDisposed
    return unless defined?($browser) && $browser && !$browser.isDisposed

    area = $surface_parent.getClientArea
    $browser.setBounds(0, 0, area.width, area.height)
    sync_embedded_browser_surfaces
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
    div span p a strong button
    form label fieldset legend
    ul ol li
    main section article aside footer
    table thead tbody tr th td
    h1 h2 h3 h4 h5 h6
    br hr
    svg path
    overlay-page
    embedded-browser
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

  def self.browserFunctionFac(browser, callback_name)
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
    end.new(browser, callback_name)
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
      Frontend.browserFunctionFac(@browser, callback_name)

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
            #{Frontend.overlay_bridge_script}
            #{Frontend.embedded_browser_bridge_script}
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
          render_nodes(instance_eval(&block))
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

    def overlay_page_element(id:, url: nil, html: nil, alpha: 255, x: nil, y: nil, width: nil, height: nil,
                             x_ratio: nil, y_ratio: nil, width_ratio: nil, height_ratio: nil, **attrs, &block)
      geometry_callback = Frontend.register_overlay_geometry_callback(@parent_renderer.browser, id)

      Frontend.register_overlay_page(
        id,
        {
          url: url,
          html: html,
          alpha: alpha,
          bounds: {
            x: x,
            y: y,
            width: width,
            height: height,
            x_ratio: x_ratio,
            y_ratio: y_ratio,
            width_ratio: width_ratio,
            height_ratio: height_ratio
          }.compact
        }
      )

      overlay_attrs = attrs.merge(
        id: id,
        data_overlay_host: "true",
        data_overlay_geometry_callback: geometry_callback,
        data_overlay_url: url,
        data_overlay_html: html,
        data_overlay_alpha: alpha,
        data_overlay_x: x,
        data_overlay_y: y,
        data_overlay_width: width,
        data_overlay_height: height,
        data_overlay_x_ratio: x_ratio,
        data_overlay_y_ratio: y_ratio,
        data_overlay_width_ratio: width_ratio,
        data_overlay_height_ratio: height_ratio
      )

      tag("overlay-page", **overlay_attrs, &block)
    end

    def embedded_browser_element(id:, url: nil, html: nil, visible: true, x: nil, y: nil, width: nil, height: nil, **attrs, &block)
      geometry_callback = Frontend.register_embedded_browser_geometry_callback(@parent_renderer.browser, id)
      host_content = attrs.delete(:host_content) || ""
      embedded_html =
        if block
          build_embedded_browser_document(render_nodes(instance_eval(&block)))
        elsif html
          warn "[embedded_browser_element] html: está deprecado; prefira conteúdo via bloco de tags."
          html
        else
          nil
        end

      Frontend.register_embedded_browser(
        id,
        {
          url: url,
          html: embedded_html,
          visible: visible,
          bounds: {
            x: x,
            y: y,
            width: width,
            height: height
          }.compact
        }
      )

      embedded_attrs = attrs.merge(
        id: id,
        data_embedded_browser_host: "true",
        data_embedded_browser_geometry_callback: geometry_callback,
        data_embedded_browser_url: url,
        data_embedded_browser_html: embedded_html,
        data_embedded_browser_visible: visible
      )

      tag("embedded-browser", host_content, **embedded_attrs)
    end

    def render_nodes(result)
      components = result.is_a?(Array) ? result : [result]

      components.map do |c|
        add_child(c) if c.is_a?(Component)
        c.is_a?(Component) ? c.render_to_html : c.to_s
      end.join
    end

    def build_embedded_browser_document(inner_html)
      <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset="UTF-8">
            <style>
              html, body {
                margin: 0;
                padding: 0;
                width: 100%;
                height: 100%;
              }
            </style>
          </head>
          <body>
            #{inner_html}
          </body>
        </html>
      HTML
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
    Frontend.ensure_frontend_runtime!
    $display.async_exec { block.call }
  end

  def self.ensure_frontend_runtime!
    return if defined?($display) && $display && !$display.isDisposed

    $display = Display.new
    $shell   = Shell.new($display)
    $shell.setLayout(FillLayout.new)
    $surface_parent = Composite.new($shell, 0)
    $surface_parent.setLayout(nil)
    $embedded_surfaces = {}

    $browser = Browser.new($surface_parent, 0)
    $root    = RootRenderer.new($browser)

    frontend_resize_listener = Listener.impl { |_event| Frontend.sync_frontend_layout! rescue nil }
    $shell.addListener(SWT::Resize, frontend_resize_listener)
    $surface_parent.addListener(SWT::Resize, frontend_resize_listener)

    @server_thread ||= Thread.new { server.start }
  end

  def self.start!
    ensure_frontend_runtime!
    $shell.open
    sync_frontend_layout!
    $display.async_exec do
      $browser.setUrl("#{base_url}/index.html")
    end
    self.run_loop
  end
  
  def self.run_loop
		ensure_frontend_runtime!
		while !$shell.disposed?
			$display.sleep unless $display.read_and_dispatch
		end
    $display.dispose
  end

end
