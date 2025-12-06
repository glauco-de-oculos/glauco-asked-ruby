Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require 'json'
require 'fileutils'
require 'open3'
require 'securerandom'

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

class GlaucoPlastic
  
  LMS_EXE_PATH     = File.expand_path(File.join(Dir.home, ".lmstudio", "bin", "lms.exe"))
  MODEL_PATH       = File.expand_path("vendor/Qwen3-4B-Instruct-2507-Q4_K_M.gguf", __dir__)
  MODEL_IDENTIFIER = "qwen3"
  SERVER_PORT      = 1234

  puts "[Glauco] 🚀 Inicializando Glauco Framework..."

  # ===========================================================
  # 🧠 Inicialização do LM Studio 
  # ===========================================================
  def initialize

    puts "[Glauco] 🚀 Configurando Glauco Framework..."
    
    require 'ruby_llm'

    puts "[Glauco] ⚙️ Configuração inicial..."

    start_lmstudio

  end

  private
  def start_lmstudio
    puts "[LMStudio] 🚀 Iniciando LM Studio..."
    
    $lm_mutex ||= Mutex.new
    $lmstudio_started ||= false
    @lmstudio_ready = false

    Thread.new do
      $lm_mutex.synchronize do
        begin
          if !$lmstudio_started
            $lmstudio_started = true

            lmstudio_home = File.expand_path(File.join(Dir.home, ".lmstudio"))
            template_src  = File.expand_path("vendor/.lmstudio", __dir__)

            unless Dir.exist?(lmstudio_home)
              puts "[LMStudio] 🧱 Local .lmstudio não encontrado. Copiando template..."
              FileUtils.cp_r(template_src, lmstudio_home)
            else
              puts "[LMStudio] ⚙️ Ambiente LM Studio já existente."
              system(LMS_EXE_PATH, "ls")
              sleep 2
            end

            puts "[LMStudio] 🚀 Importando modelo..."
            system(LMS_EXE_PATH, "import", MODEL_PATH, "-y", "--hard-link")

            puts "[LMStudio] 🧩 Carregando modelo..."
            gpu_mode = ENV["LMS_GPU_MODE"] || "max" # padrão configurável
            system(LMS_EXE_PATH,
              "load", "qwen/qwen3-4b-2507",
              "--gpu", gpu_mode,
              "--identifier", MODEL_IDENTIFIER,
              "--context-length", "8192",
              "-y"
            )

             # realizar carregamento de modelo de embeddings Qwen3-Embedding-4B-Q4_K_M.gguf
            system(LMS_EXE_PATH, "import", File.expand_path("vendor/Qwen3-Embedding-4B-Q4_K_M.gguf", __dir__), "-y", "--hard-link")
            sleep 1
            system(LMS_EXE_PATH,
              "load", "Qwen/Qwen3-Embedding-4B-GGUF/Qwen3-Embedding-4B-Q4_K_M.gguf",
              "--gpu", gpu_mode,
              "--identifier", "qwen3-embedding",
              "--context-length", "8192",
              "-y"
            )

            puts "[LMStudio] 🔌 Iniciando servidor na porta #{SERVER_PORT}..."
            system(LMS_EXE_PATH, "server", "start", "--port", SERVER_PORT.to_s)

            # Espera a porta estar disponível
            wait_for_http_ready(SERVER_PORT)
            @lmstudio_ready = true
            puts "[LMStudio] ✅ Servidor pronto em http://localhost:#{SERVER_PORT}"
          else
            puts "[LMStudio] ⚙️ Reaproveitando servidor existente."
            wait_for_http_ready(SERVER_PORT)
            @lmstudio_ready = true
          end
        rescue => e
          puts "[LMStudio] ❌ Falha ao iniciar servidor: #{e.class} - #{e.message}"
        end
      end
    end

    # Espera sincronamente até LM Studio estar pronto
    start = Time.now
    until @lmstudio_ready
      sleep 0.2
      raise "Timeout ao aguardar LM Studio" if Time.now - start > 60
    end
  end

  def setup_llm(system_config_instructions:, domain_specific_knowledge: nil)
    require 'ruby_llm'

    puts "[LLM] 🚀 Extraindo lista de funções da API..."

    puts "[LLM] 🚀 Configurando RubyLLM com LM Studio..."

    RubyLLM.configure do |config|
      # LM Studio não exige chave, mas o campo é obrigatório
      config.openai_api_key = "lmstudio-local"

      # endpoint local do LM Studio (compatível com OpenAI API)
      config.openai_api_base = "http://localhost:1234/v1"
    end

    puts "[LLM] 🚀 Preparando chat com modelo #{MODEL_IDENTIFIER}..."

    @chat = RubyLLM::Chat.new(
      model: "#{MODEL_IDENTIFIER}",
      provider: :openai,
      assume_model_exists: true
      )

    puts "[LLM] 🚀 Configurando temperatura do modelo..."
      
    @chat.with_temperature(0.0)

    @config_path = File.expand_path(system_config_instructions)
    puts "[LLM] 🚀 Carregando instruções... #{@config_path}"

    @domain_specific_knowledge = domain_specific_knowledge
    # return if File.exist?("rag_index.json")  # já existe, não refaz
    carregar_base_de_conhecimento
    
    puts "[LLM] ✅ Configuração do LLM concluída."
    
    @chat
  end

  def carregar_base_de_conhecimento

    full_text = File.read(@domain_specific_knowledge, encoding: "UTF-8")
    chunks = full_text.split(/^###\s+/).map(&:strip).reject(&:empty?)

    @rag_index = RagIndex.build(chunks)
    RagIndex.save(@rag_index)

    puts "[LLM] 🚀 Carregando instruções de configuração do sistema... #{@config_path} "

    @chat.with_instructions(File.read(@config_path, encoding: "UTF-8"), replace: true)

    
  end

  def wait_for_http_ready(port, host: "localhost", timeout: 30)
    puts "[LMStudio] ⏳ Aguardando LM Studio na porta #{port}..."
    start = Time.now
    loop do
      puts "[LMStudio] 🔍 Tentando conectar na porta #{port}..."
      begin
        TCPSocket.new(host, port).close
        puts "[LMStudio] 🔗 Porta #{port} está pronta."
        return true
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
        sleep 0.5
        raise "Timeout ao aguardar LM Studio na porta #{port}" if Time.now - start > timeout
      end
    end
  end

  public
  def interpretar(input_text)
    query_vector = RubyLLM.embed(input_text).vectors

    results = RagIndex.search(@rag_index, query_vector, k: 3)
    context = results.map(&:text).join("\n\n")

    prompt = <<~PROMPT
      ## Contexto relevante:
      #{context}

      ## Pedido do usuário:
      "#{input_text}"

    PROMPT

    prompt
  end


end