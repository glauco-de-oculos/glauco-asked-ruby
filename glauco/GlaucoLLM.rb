Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require 'json'
require 'fileutils'
require 'open3'
require 'securerandom'
require 'ruby_llm'

BASE_DIR = File.dirname(__FILE__)

require "json"
require "matrix"
require "base64"

module RagIndex
  IndexEntry = Struct.new(:id, :text, :vector)

  # ---------------------------------------------
  # 🔨 Build (cria o índice vetorial)
  # ---------------------------------------------
  def self.build(texts)
    puts "[RAG] 🔨 Gerando #{texts.size} embeddings..."

    embeddings = RubyLLM.embed(texts)
    vectors = embeddings.vectors

    index = []

    texts.each_with_index do |text, i|
      vec = Vector.elements(vectors[i])
      index << IndexEntry.new(i, text, vec)
    end

    puts "[RAG] 📦 Indexados #{index.size} chunks"
    index
  end

  # ---------------------------------------------
  # 💾 Salvar índice em arquivo (persistente)
  # ---------------------------------------------
  def self.save(index, path: "rag_index.json", store_path: "rag_store.json")
    json_data = index.map do |e|
      {
        id: e.id,
        text: e.text,
        vector: Base64.strict_encode64(e.vector.to_a.pack("E*")) # compacta float32
      }
    end

    File.write(path, JSON.pretty_generate(json_data), encoding: "UTF-8")

    # salva texto bruto para eventuais reindexações
    File.write(store_path,
      JSON.pretty_generate(index.map(&:text)),
      encoding: "UTF-8"
    )

    puts "[RAG] 💾 Índice salvo em #{path}"
    puts "[RAG] 💾 Armazenamento salvo em #{store_path}"
  end

  # ---------------------------------------------
  # 📂 Carregar índice salvo (instantâneo)
  # ---------------------------------------------
  def self.load(path: "rag_index.json")
    json = JSON.parse(File.read(path, encoding: "UTF-8"))

    json.map do |e|
      raw = Base64.decode64(e["vector"])
      floats = raw.unpack("E*")
      vec = Vector.elements(floats)

      IndexEntry.new(e["id"], e["text"], vec)
    end
  end

  # ---------------------------------------------
  # 🔍 Cosine Similarity
  # ---------------------------------------------
  def self.cosine(a, b)
    a.inner_product(b) / (a.norm * b.norm)
  end

  # ---------------------------------------------
  # 🔎 FAISS-like similarity search
  # ---------------------------------------------
  def self.search(index, query_vector, k: 5)
    q = Vector.elements(query_vector)

    scored = index.map do |entry|
      score = cosine(q, entry.vector)
      [entry, score]
    end

    scored.sort_by { |(_, score)| -score }
          .first(k)
          .map(&:first)
  end
end

module RLM

  # ---------------------------
  # AGENT
  # ---------------------------
  class Agent
    attr_reader :vars, :history, :endpoint

    SYSTEM = <<~SYS
      #You are an RLM agent.

      ##STRICT RULES:
      - ALWAYS use ```repl``` blocks
      - NEVER answer directly outside ```repl```
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

    def initialize(
      model: "local-gguf",
      endpoint: "http://127.0.0.1:8080/v1",
      initial_vars: {},
      runtime: nil
    )
      @model = model
      @endpoint = endpoint

      # ---------------------------
      # 🔑 runtime como instância única
      # ---------------------------
      @runtime =
        if runtime.is_a?(Module)
          Object.new.extend(runtime)
        else
          runtime
        end

      # ---------------------------
      # 🔑 métodos disponíveis no runtime
      # ---------------------------
      @runtime_methods =
        if @runtime
          @runtime.public_methods(false).map(&:to_s)
        else
          []
        end

      # ---------------------------
      # vars
      # ---------------------------
      @initial_vars = initial_vars.transform_keys(&:to_s)
      @vars = @initial_vars.dup
      @history = []
    end

    # ---------------------------
    # MAIN LOOP
    # ---------------------------
    def run(input, max_iter: 8)
      vars.delete("answer")
      @last_code = nil

      max_iter.times do
        if vars.key?("answer")
          puts "[AGENT] 🛑 answer already exists, stopping loop"
          return vars["answer"]
        end
        puts "[AGENT] step..."
        # puts "[DEBUG VARS] #{vars.inspect}"

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
          end

          @last_code = code

          out, _ = execute(code)
          out = clean_utf8(out)

          puts "[RESULT] #{out}"

          # 🔑 ESSA LINHA RESOLVE TUDO
          if vars.key?("answer")
            puts "[AGENT] ✅ final answer detected, stopping"
            return vars["answer"]
          end
        end

        history << msg(:assistant, text)
      end

      "No final answer"
    end

    # ---------------------------
    # CHAT (ENDPOINT ONLY)
    # ---------------------------
    def build_chat
      RubyLLM.configure do |c|
        c.openai_api_base = @endpoint
        c.openai_api_key  = "local"
      end

      RubyLLM.chat(
        model: @model,
        provider: :openai,
        assume_model_exists: true
      )
    end

    def reset!
      @vars = @initial_vars.dup
      @history.clear

      puts @vars, @history
    end


    # ---------------------------
    # EXECUTION ENGINE
    # ---------------------------
    def execute(code)
      ctx = @runtime
      raise "runtime not configured" unless ctx

      # inject vars
      vars.each do |k,v|
        ctx.instance_variable_set("@#{k}", v)
      end

      result = ctx.instance_eval(code)

      # 🔑 REGRA PRINCIPAL
      # o valor do último statement vira answer
      vars["answer"] = result unless result.nil?

      [result, vars.keys]

    rescue => e
      puts "[EXEC ERROR] #{e.class} - #{e.message}"
      puts e.backtrace.first(10)
      ["ERROR: #{e.class} - #{e.message}", []]
    end
    # ---------------------------
    # PROMPT
    # ---------------------------
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
    
    # ---------------------------
    # TOOL HANDLING
    # ---------------------------
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
    # ---------------------------
    # HELPERS
    # ---------------------------
    def msg(role, content)
      { role: role, content: clean_utf8(content) }
    end

    def extract_repl(text)
      text.scan(/```(?:repl|ruby)\n(.*?)```/m).flatten
    end

    def clean_utf8(s)
      s.to_s.force_encoding("UTF-8")
        .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    end
  end
  # ---------------------------
  # TEST SUITE
  # ---------------------------
  module TestSuite

    TestCase = Struct.new(
      :name, :input, :initial_vars, :expect, :verify_with_llm,
      keyword_init: true
    )

    class Runner
      attr_reader :cases, :results

      def initialize(agent:, model: "local-gguf", cases: [])
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
end

class GlaucoLLM

  DEFAULT_ENDPOINT = "http://127.0.0.1:8080/v1"
  DEFAULT_MODEL    = "local-gguf"

  def initialize(
    endpoint: DEFAULT_ENDPOINT,
    model: DEFAULT_MODEL
  )
    puts "[Glauco] 🚀 Inicializando Glauco Framework (RLM core)..."

    @endpoint = endpoint
    @model = model

    @agent = nil
    @config_path = nil
    @domain_specific_knowledge = nil
  end

  # ===========================================================
  # 🧠 setup_llm (mantido)
  # ===========================================================
  def setup_llm(system_config_instructions:, domain_specific_knowledge: nil)
    puts "[LLM] 🚀 setup_llm (vars-only mode)"

    @config_path = File.expand_path(system_config_instructions)
    @domain_specific_knowledge = domain_specific_knowledge

    initial_vars = {}

    # ---------------------------
    # system_config → VAR
    # ---------------------------
    if File.exist?(@config_path)
      system_config = File.read(@config_path, encoding: "UTF-8")
      initial_vars["system_config"] = system_config
    else
      raise "system_config_instructions não encontrado: #{@config_path}"
    end

    # ---------------------------
    # domain_knowledge → VAR
    # ---------------------------
    if @domain_specific_knowledge && File.exist?(@domain_specific_knowledge)
      knowledge = File.read(@domain_specific_knowledge, encoding: "UTF-8")
      initial_vars["domain_knowledge"] = knowledge
    end

    # ---------------------------
    # criar agent
    # ---------------------------
    @agent = RLM::Agent.new(
      model: @model,
      endpoint: @endpoint,
      initial_vars: initial_vars
    )

    puts "[LLM] ✅ Agent pronto (vars: system_config, domain_knowledge)"
    @agent
  end

  # ===========================================================
  # execução
  # ===========================================================
  def interpretar(input_text)
    raise "LLM não inicializado. Chame setup_llm primeiro." unless @agent

    @agent.run(input_text)
  end

  # ===========================================================
  # extras
  # ===========================================================
  def reset!
    @agent&.reset!
  end

  def vars
    @agent&.vars
  end

  def history
    @agent&.history
  end

  def test_runner(cases: [])
    RLM::TestSuite::Runner.new(
      agent: @agent,
      model: @model,
      cases: cases
    )
  end
end