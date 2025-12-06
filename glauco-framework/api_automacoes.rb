module ApiAutomacoes
  
  require 'json'
  require 'fileutils'
  require 'forwardable'
  require 'ruby_llm'



  class AbrirUrlTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Abre uma URL no navegador. É um alias simples para OpenUrlTool."

    params do
      string :url, description: "A URL completa para abrir (ex: 'https://google.com')."
    end

    def execute(url:)
      # 💥 IMPLEMENTAÇÃO DE abrir_url(url:)
      browser.setUrl(url)
    end
  end

  class VoltarTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Navega para a página anterior no histórico do navegador."

    def execute
      # 💥 IMPLEMENTAÇÃO DE voltar
      action = WebAction.new
      run_ui do
        begin
          if browser.isBackEnabled
            browser.back
            state[:last_action] = "voltar"
            puts "[Navegação] ⬅️ Voltar no histórico"
            action.resolve("back")
          else
            puts "[Navegação] ℹ️ Não há histórico para voltar"
            action.resolve("no_history")
          end
        rescue => e
          puts "[Navegação] 💥 Erro em voltar: #{e.class} - #{e.message}"
          action.resolve(nil)
        end
      end
      action
    end
  end


  # ====================================
  # 🔍 Input Web
  # ====================================

  class DigitarTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Digita um valor em um campo de formulário identificado por um seletor CSS. É o wrapper em português para 'type'."

    params do
      string :selector, description: "Seletor CSS do campo de input (ex: '#campo-busca')."
      string :valor, description: "O texto a ser digitado no campo."
    end

    def execute(selector:, valor:)
      # 💥 IMPLEMENTAÇÃO DE digitar (que é um wrapper de type)
      # Inlining a lógica de `type` e substituindo `value` por `valor`.
      puts "[Input] ⌨️ digitando no #{selector.inspect} o valor #{valor.inspect}"
      action = WebAction.new
      run_ui do
        js = <<~JS
          var el = document.querySelector("#{selector}");
          if (el) { el.value = "#{valor}"; el.dispatchEvent(new Event('input', {bubbles: true})); "typed"; }
          else "element not found";
        JS
        begin
          result = evaluate(js, "type:#{selector}")
          puts "[DigitarTool] result: #{result}"
          action.resolve("typed")
        rescue => e
          puts "[Type] 💥 Erro: #{e.class} - #{e.message}"
          action.resolve(nil)
        end
      end
      action
    end
  end

  class PressionarEnterTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Simula o pressionamento da tecla Enter. Aplica ao elemento ativo ou a um seletor específico."

    # CORRIGIDO: Retornando ao DSL simples (sem default), pois o parâmetro é opcional.
    params do
      string :selector, description: "Seletor CSS opcional do elemento onde pressionar Enter."
    end

    def execute(selector: nil)
      # 💥 IMPLEMENTAÇÃO DE pressionar_enter (que chama hotkey)
      key = 'Enter'

      puts "[Hotkey] ⌨️ pressionar_enter no selector=#{selector.inspect}"
      action = WebAction.new
      run_ui do
        begin
          js = if selector
            <<~JS
              var el = document.querySelector("#{selector}");
              if (!el) return "element not found";
              var event = new KeyboardEvent('keydown', {
                key: "#{key}",
                code: "#{key}",
                keyCode: #{key == 'Enter' ? 13 : 0},
                which: #{key == 'Enter' ? 13 : 0},
                bubbles: true
              });
              el.dispatchEvent(event);
              if (el.form) el.form.submit();
              "key dispatched";
            JS
          else
            <<~JS
              var event = new KeyboardEvent('keydown', {
                key: "#{key}",
                code: "#{key}",
                keyCode: #{key == 'Enter' ? 13 : 0},
                which: #{key == 'Enter' ? 13 : 0},
                bubbles: true
              });
              document.activeElement.dispatchEvent(event);
              if (document.activeElement.form) document.activeElement.form.submit();
              "key dispatched to active element";
            JS
          end

          result = browser.evaluate(js)
          puts "[Hotkey] selector=#{selector.inspect} key=#{key} → #{result.inspect}"
          action.resolve(result)
        rescue => e
          puts "[Hotkey] 💥 Erro: #{e.class} - #{e.message}"
          action.resolve(nil)
        end
      end
      action
    end
  end

  class LimparTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Limpa o valor de um campo de input identificado por um seletor CSS."

    params do
      string :selector, description: "Seletor CSS do campo de input a ser limpo (ex: '#username-field')."
    end

    def execute(selector:)
      # 💥 IMPLEMENTAÇÃO DE limpar
      action = WebAction.new
      run_ui do
        js = <<~JS
          (function(){
            var selector = #{selector.to_json};
            var el = document.querySelector(selector);
            if (el) {
              el.value = "";
              el.dispatchEvent(new Event('input', {bubbles: true}));
              return "cleared";
            } else {
              return "element not found";
            }
          })();
        JS

        begin
          result = evaluate(js, "limpar:#{selector}")
          puts "[Input] 🧽 limpar(#{selector.inspect}) → #{result.inspect}"
          action.resolve(result)
        rescue => e
          puts "[Input] 💥 Erro em limpar: #{e.class} - #{e.message}"
          action.resolve(nil)
        end
      end
      action
    end
  end

  # ====================================
  # 🖱️ Clique Web
  # ====================================

  class ClicarTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Clica em um elemento identificado por um seletor CSS. É o wrapper em português para 'click'."

    params do
      string :selector, description: "Seletor CSS do elemento a ser clicado (ex: 'button.submit')."
    end

    def execute(selector:)
      # 💥 IMPLEMENTAÇÃO DE clicar (que é um wrapper de click)
      # Inlining a lógica de `click`.
      action = WebAction.new
      run_ui do
        begin
          js = <<~JS
            var el = document.querySelector("#{selector}");
            if (el) {
              el.click();
              "clicked";
            } else {
              "element not found";
            }
          JS

          result = evaluate(js, "click:#{selector}")
          puts "[Click] 🖱️ Clique no elemento #{selector.inspect} → #{result.inspect}"
          action.resolve(result)
        rescue => e
          puts "[Click] 💥 Erro: #{e.class} - #{e.message}"
          action.resolve(nil)
        end
      end
      action
    end
  end

  # ====================================
  # 📋 Inspeção Web
  # ====================================

  class LerHtmlTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Retorna o código HTML completo da página web atual (`document.document.body.outerHTML`)."

    def execute
      # 💥 IMPLEMENTAÇÃO DE ler_html
      action = WebAction.new
      run_ui do
        js = "return document.body.outerHTML;"
        begin
          html = evaluate(js, "ler_html")
          puts "[Inspect] 📄 ler_html → tamanho=#{html.to_s.length} chars"
          action.resolve(html.to_s)
        rescue => e
          puts "[Inspect] 💥 Erro em ler_html: #{e.class} - #{e.message}"
          action.resolve(nil)
        end
      end
      action
    end
  end



  class AguardarTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Aguarda até que um elemento identificado pelo seletor CSS apareça na página, dentro de um tempo limite."

    # CORRIGIDO: Removido `:timeout_ms` e `:intervalo_ms` do schema.
    params type: "object",
      properties: {
        selector: { type: "string", description: "Seletor CSS do elemento a ser aguardado." }
      },
      required: %w[selector],
      additionalProperties: false,
      strict: true

    def execute(selector:, timeout_ms: 10_000, intervalo_ms: 250)
      # 💥 IMPLEMENTAÇÃO DE aguardar
      action = WebAction.new

      puts "[Aguardar] ⏳ Iniciando aguardo por #{selector.inspect} até #{timeout_ms}ms"

      run_ui do # Assumindo que Agente.run_in_thread está disponível
        start_time = Time.now
        found = false

        puts "[Aguardar] ⏳ Aguardando #{selector.inspect} por até #{timeout_ms}ms"

        while (Time.now - start_time) * 1000 < timeout_ms && !found
          begin
            js = <<~JS
              (function(){
                var selector = #{selector.to_json};
                return !!document.querySelector(selector);
              })();
            JS

            # Assumindo que evaluate está disponível no contexto
            result = evaluate(js, "aguardar:#{selector}")
            found = !!result
          rescue => e
            puts "[Aguardar] 💥 Erro: #{e.class} - #{e.message}"
          end

          break if found
          sleep(intervalo_ms / 1000.0)
        end

        puts "[Aguardar] ✅ Resultado para #{selector.inspect}: #{found}"
        action.resolve(found)
      end

      action
    end
  end


  # ====================================
  # 🗃️ Sistema de Arquivos (FS)
  # ====================================

  class FsPastaAtualTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Retorna o caminho completo do diretório de trabalho atual (Current Working Directory - CWD)."

    def execute
      # 💥 IMPLEMENTAÇÃO DE fs_pasta_atual
      puts "📂 Ação: FS -> Retornar o caminho do diretório de trabalho atual."
      return Dir.pwd
    rescue => e
      puts "❌ Erro FS: Falha ao obter diretório atual: #{e.message}"
      return nil
    end
  end

  class ListarArquivosEmPastaTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Lista todos os arquivos e pastas no caminho base, exibindo a estrutura de árvore. Útil para visão geral."

    # CORRIGIDO: Removido `:caminho_base` do schema (que tem default: ".").
    params type: "object",
      properties: {},
      required: [],
      additionalProperties: false,
      strict: true

    def execute(caminho_base: '.')
      # 💥 IMPLEMENTAÇÃO DE listar_arquivos_em_pasta
      caminho = caminho_base.to_s.strip
      caminho = '.' if caminho.empty?
      caminho = File.expand_path(caminho)
      # Use tree command for a visual list (Windows specific command used here)
      raw = IO.popen(%W[cmd /c tree "#{caminho}" /F /A], "r:bom|utf-8") { |io| io.read }
      # Force encoding conversion (Windows → UTF-8)
      output = raw.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      output
    rescue => e
      "❌ Erro ao listar arquivos: #{e.message}"
    end
  end

  class FsListarArquivosTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Lista arquivos e pastas dentro de um diretório específico (NÃO recursivo)."

    params do
      string :path_diretorio, description: "O caminho para o diretório a ser listado."
    end

    def execute(path_diretorio:)
      # 💥 IMPLEMENTAÇÃO DE fs_listar_arquivos
      puts "[FS] 📂 Listando conteúdo de: #{path_diretorio.inspect}"
      # path_diretorio aqui é a variável path do escopo da função original
      begin
        abs = File.expand_path(path_diretorio)
        itens = Dir.children(abs).map do |f|
          tipo = File.directory?(File.join(abs, f)) ? "dir" : "file"
          { nome: f, tipo: tipo }
        end
        puts "[FS] ✔️ #{itens.length} itens encontrados"
        itens
      rescue => e
        puts "[FS] ❌ Erro em fs_listar: #{e.class} - #{e.message}"
        []
      end
    end
  end

  class FsListarRecursivoTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Lista recursivamente todos os arquivos e pastas a partir de um diretório base."

    params do
      string :path_diretorio, description: "O caminho para o diretório base da listagem recursiva."
    end

    def execute(path_diretorio:)
      # 💥 IMPLEMENTAÇÃO DE fs_listar_recursivo
      puts "[FS] 🌳 Listagem recursiva de: #{path_diretorio.inspect}"
      begin
        abs = File.expand_path(path_diretorio)
        lista = Dir.glob("#{abs}/**/*").map do |item|
          { caminho: item, tipo: File.directory?(item) ? "dir" : "file" }
        end
        puts "[FS] ✔️ #{lista.length} itens recursivos"
        lista
      rescue => e
        puts "[FS] ❌ Erro em fs_listar_recursivo: #{e.class} - #{e.message}"
        []
      end
    end
  end

  class FsBuscarTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Busca arquivos por nome/padrão (glob) de forma recursiva (ex: '*.pdf', '*contrato*')."

    # CORRIGIDO: Removido `:path` e `:padrao` do schema (que têm default: "." e "*").
    params type: "object",
      properties: {},
      required: [],
      additionalProperties: false,
      strict: true

    def execute(path: ".", padrao: "*")
      # 💥 IMPLEMENTAÇÃO DE fs_buscar
      puts "[FS] 🔎 Buscando #{padrao.inspect} em #{path.inspect}"
      begin
        abs = File.expand_path(path)
        resultados = Dir.glob("#{abs}/**/#{padrao}")
        puts "[FS] ✔️ #{resultados.length} resultados"
        resultados
      rescue => e
        puts "[FS] ❌ Erro em fs_buscar: #{e.class} - #{e.message}"
        []
      end
    end
  end

  class FsBuscarContextualTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Busca arquivos por nome e conteúdo (para arquivos de texto não muito grandes) usando uma lista de termos."

    # CORRIGIDO: Removido `:path` e `:termos` do schema (que têm default: "." e []).
    params type: "object",
      properties: {},
      required: [],
      additionalProperties: false,
      strict: true

    def execute(path: ".", termos: [])
      # 💥 IMPLEMENTAÇÃO DE fs_buscar_contextual
      termos = Array(termos).map(&:downcase)
      puts "[FS] 🧠 Busca contextual em #{path.inspect}, termos=#{termos.inspect}"
      begin
        # Depende de fs_listar_recursivo, que está no mesmo módulo (e deve estar disponível no contexto)
        arquivos = fs_listar_recursivo(path).select { |x| x[:tipo] == "file" }
        encontrados = []
        arquivos.each do |info|
          caminho = info[:caminho]
          nome = File.basename(caminho).downcase

          # Primeira camada: nome do arquivo
          match_nome = termos.all? { |t| nome.include?(t) }

          # Segunda camada: conteúdo (somente se não for muito grande)
          match_conteudo = false
          begin
            if File.size(caminho) < 500_000 # 500 KB limite para leitura rápida
              conteudo = File.read(caminho).downcase rescue ""
              match_conteudo = termos.all? { |t| conteudo.include?(t) }
            end
          rescue
          end

          if match_nome || match_conteudo
            encontrados << caminho
          end
        end
        puts "[FS] ✔️ Encontrados #{encontrados.length} arquivos"
        encontrados
      rescue => e
        puts "[FS] ❌ Erro em fs_buscar_contextual: #{e.class} - #{e.message}"
        []
      end
    end

    # Método auxiliar para fs_buscar_contextual (cópia da lógica)
    private def fs_listar_recursivo(path_diretorio)
      # Lógica simplificada de fs_listar_recursivo, assumindo que Dir.glob é suficiente
      abs = File.expand_path(path_diretorio)
      Dir.glob("#{abs}/**/*").map do |item|
        { caminho: item, tipo: File.directory?(item) ? "dir" : "file" }
      end
    end
  end

  # ====================================
  # 📄 Leitura de Arquivos (FS)
  # ====================================

  class FsLerTextoTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Lê o conteúdo de um arquivo como texto puro (UTF-8)."

    params do
      string :path, description: "O caminho para o arquivo a ser lido."
    end

    def execute(path:)
      # 💥 IMPLEMENTAÇÃO DE fs_ler_texto
      puts "[FS] 📄 Lendo arquivo como texto: #{path.inspect}"
      begin
        conteudo = File.read(path, encoding: "UTF-8")
        puts "[FS] ✔️ #{conteudo.length} chars lidos"
        conteudo
      rescue => e
        puts "[FS] ❌ Erro em fs_ler_texto: #{e.class} - #{e.message}"
        nil
      end
    end
  end

  class FsLerPdfTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Lê e extrai o texto de um arquivo PDF."

    params do
      string :path, description: "O caminho para o arquivo PDF."
    end

    def execute(path:)
      # 💥 IMPLEMENTAÇÃO DE fs_ler_pdf (chama ler_pdf)
      puts "[FS] 📄 Lendo PDF: #{path.inspect}"
      ler_pdf(path)
    end
  end

  class FsLerPlanilhaTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Lê o conteúdo de um arquivo XLSX ou similar, retornando os dados como uma estrutura de tabela (Array de Arrays)."

    params do
      string :path, description: "O caminho para o arquivo de planilha."
    end

    def execute(path:)
      # 💥 IMPLEMENTAÇÃO DE fs_ler_planilha (chama ler_xlsx)
      puts "[FS] 📊 Lendo planilha: #{path.inspect}"
      ler_xlsx(path)
    end
  end

  class FsInferirTipoTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Infere o tipo de arquivo (e.g., 'texto', 'pdf', 'planilha', 'imagem') com base na sua extensão."

    params do
      string :ext, description: "A extensão do arquivo (e.g., '.pdf', '.xlsx')."
    end

    def execute(ext:)
      # 💥 IMPLEMENTAÇÃO DE fs_inferir_tipo
      ext = ext.to_s.downcase
      case ext
      when ".txt", ".md", ".rb", ".js", ".json", ".csv", ".html"
        "texto"
      when ".pdf"
        "pdf"
      when ".xlsx", ".xls", ".ods", ".csv"
        "planilha"
      when ".png", ".jpg", ".jpeg"
        "imagem"
      when ".docx"
        "word"
      else
        "desconhecido"
      end
    end
  end

  class LerArquivoTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Tenta ler um arquivo, determinando o método de leitura mais adequado com base na extensão (PDF, DOCX, XLSX ou texto simples)."

    params do
      string :caminho_arquivo, description: "O caminho para o arquivo a ser lido."
    end

    def execute(caminho_arquivo:)
      # 💥 IMPLEMENTAÇÃO DE ler_arquivo
      extensao = File.extname(caminho_arquivo).downcase
      puts "📂 Tentando ler o arquivo: **#{caminho_arquivo}** (Extensão: #{extensao})"
      case extensao
      when '.pdf'
        return ler_pdf(caminho_arquivo)
      when '.docx'
        return ler_docx(caminho_arquivo)
      when '.xlsx'
        return ler_xlsx(caminho_arquivo)
      else
        puts "⚠️ Tipo de arquivo não suportado para leitura dinâmica: #{extensao}"
        return File.read(caminho_arquivo) # Tenta ler como texto simples
      end
    rescue Errno::ENOENT
      return "❌ Erro: Arquivo não encontrado no caminho '#{caminho_arquivo}'."
    rescue => e
      return "❌ Erro geral na leitura do arquivo: #{e.message}"
    end
  end

  # ====================================
  # ✏️ Manipulação de Arquivos (FS)
  # ====================================

  class FsCopiarTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Copia um arquivo de um local para outro."

    params do
      string :origem, description: "Caminho do arquivo ou pasta de origem."
      string :destino, description: "Caminho para onde o arquivo ou pasta será copiado."
    end

    def execute(origem:, destino:)
      # 💥 IMPLEMENTAÇÃO DE fs_copiar
      puts "[FS] 📄 Copiando arquivo:"
      puts " origem: #{origem}"
      puts " destino: #{destino}"
      begin
        FileUtils.cp(origem, destino)
        puts "[FS] ✔️ Copiado"
        true
      rescue => e
        puts "[FS] ❌ Erro em fs_copiar: #{e.class} - #{e.message}"
        false
      end
    end
  end

  class FsMoverTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Move/renomeia um arquivo ou pasta de um local para outro."

    params do
      string :origem, description: "Caminho do arquivo ou pasta de origem."
      string :destino, description: "Caminho para onde o arquivo ou pasta será movido/renomeado."
    end

    def execute(origem:, destino:)
      # 💥 IMPLEMENTAÇÃO DE fs_mover
      puts "[FS] 📄 Movendo arquivo:"
      puts " origem: #{origem}"
      puts " destino: #{destino}"
      begin
        FileUtils.mv(origem, destino)
        puts "[FS] ✔️ Movido"
        true
      rescue => e
        puts "[FS] ❌ Erro em fs_mover: #{e.class} - #{e.message}"
        false
      end
    end
  end

  class FsDeletarTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Deleta um arquivo ou pasta (recursivamente para pastas)."

    params do
      string :path, description: "Caminho do arquivo ou pasta a ser deletado."
    end

    def execute(path:)
      # 💥 IMPLEMENTAÇÃO DE fs_deletar
      puts "[FS] 🗑️ Removendo arquivo/pasta: #{path.inspect}"
      begin
        if File.directory?(path)
          FileUtils.rm_rf(path)
        else
          FileUtils.rm(path)
        end
        puts "[FS] ✔️ Removido"
        true
      rescue Errno::ENOENT
        puts "[FS] ⚠️ Arquivo/Pasta não existe."
        true # Considerar sucesso se o alvo já não existe
      rescue => e
        puts "[FS] ❌ Erro em fs_deletar: #{e.class} - #{e.message}"
        false
      end
    end
  end

  class FsCriarPastaTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Cria uma nova pasta/diretório. Pode criar recursivamente (padrão)."

    # CORRIGIDO: Voltando ao DSL simples. `recursivo` é opcional e tem default: true.
    # Removendo o JSON Schema manual.
    params do
      string :path, description: "O caminho da pasta a ser criada."
      boolean :recursivo, description: "Se pastas pai devem ser criadas automaticamente (padrão: true)."
    end

    def execute(path:, recursivo: true)
      # 💥 IMPLEMENTAÇÃO DE fs_criar_pasta
      puts "[FS] 🗂️ Criando pasta: #{path.inspect}"
      begin
        FileUtils.mkdir_p(path) if recursivo
        FileUtils.mkdir(path) unless recursivo
        puts "[FS] ✔️ Pasta criada"
        true
      rescue => e
        puts "[FS] ❌ Erro em fs_criar_pasta: #{e.class} - #{e.message}"
        false
      end
    end
  end

  class FsCriarArquivoTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Cria um novo arquivo de texto e escreve conteúdo nele."

    # CORRIGIDO: Removido `:conteudo` do schema (que tem default: "").
    params type: "object",
      properties: {
        path: { type: "string", description: "O caminho e nome do arquivo a ser criado." }
      },
      required: %w[path],
      additionalProperties: false,
      strict: true

    def execute(path:, conteudo: "")
      # 💥 IMPLEMENTAÇÃO DE fs_criar_arquivo
      puts "[FS] 📝 Criando arquivo: #{path.inspect}"
      begin
        File.write(path, conteudo, encoding: "UTF-8")
        puts "[FS] ✔️ Arquivo criado e escrito (#{conteudo.length} chars)"
        true
      rescue => e
        puts "[FS] ❌ Erro em fs_criar_arquivo: #{e.class} - #{e.message}"
        false
      end
    end
  end

  class FsMetadataTool < RubyLLM::Tool

    extend Forwardable

    def initialize(agente_host:)
      @agente_host = agente_host
      super()
    end
    
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Retorna metadados importantes de um arquivo (tamanho, data de modificação, etc.)."

    params do
      string :path, description: "O caminho para o arquivo."
    end

    def execute(path:)
      puts "[FS] 🔍 Buscando metadados para: #{path.inspect}"
      begin
        stat = File.stat(path)
        
        # Helper para formatar o tamanho
        readable_size = begin
          units = %w(B KB MB GB TB)
          i = (Math.log(stat.size) / Math.log(1024)).to_i
          "%.2f %s" % [stat.size / (1024.0 ** i), units[i]]
        rescue
          "N/A"
        end

        metadata = {
          path: path,
          existe: true,
          tipo: File.directory?(path) ? "diretorio" : "arquivo",
          tamanho_bytes: stat.size,
          tamanho_legivel: readable_size,
          data_modificacao: stat.mtime.to_s, # Time object to String
          data_criacao: stat.ctime.to_s
        }
        puts "[FS] ✔️ Metadados encontrados"
        metadata
      rescue Errno::ENOENT
        puts "[FS] ⚠️ Arquivo não encontrado."
        { path: path, existe: false, erro: "Arquivo ou diretório não encontrado." }
      rescue => e
        puts "[FS] ❌ Erro em FsMetadataTool: #{e.message}"
        { path: path, existe: false, erro: "Erro ao acessar metadados: #{e.message}" }
      end
    end
  end

  class FsCompararTool < RubyLLM::Tool

    extend Forwardable

    def initialize(agente_host:)
      @agente_host = agente_host
      super()
    end
    
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Compara o conteúdo de dois arquivos e retorna se são idênticos."

    params do
      string :path_a, description: "Caminho para o primeiro arquivo (A)."
      string :path_b, description: "Caminho para o segundo arquivo (B)."
    end

    def execute(path_a:, path_b:)
      puts "[FS] 🔀 Comparando A: #{path_a.inspect} com B: #{path_b.inspect}"
      
      # Verifica se ambos os caminhos existem
      unless File.exist?(path_a) && File.exist?(path_b)
        return { identicos: false, erro: "Pelo menos um dos arquivos não existe." }
      end
      
      # 1. Comparação de tamanho (otimização)
      if File.size(path_a) != File.size(path_b)
        puts "[FS] ❌ Diferentes: Tamanhos não conferem."
        return { identicos: false, motivo: "Tamanhos diferentes" }
      end

      # 2. Comparação de conteúdo
      begin
        content_a = File.read(path_a)
        content_b = File.read(path_b)

        if content_a == content_b
          puts "[FS] ✔️ Arquivos idênticos."
          return { identicos: true, motivo: "Conteúdo e tamanho idênticos" }
        else
          puts "[FS] ❌ Diferentes: Conteúdo diferente (mesmo tamanho)."
          return { identicos: false, motivo: "Conteúdo diferente" }
        end
      rescue => e
        puts "[FS] ❌ Erro ao ler conteúdo: #{e.message}"
        return { identicos: false, erro: "Erro de leitura de arquivo: #{e.message}" }
      end
    end
  end

  # ====================================
  # 📊 Manipulação de Planilhas/Documentos
  # ====================================

  class CriarXlsxTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Cria um novo arquivo XLSX (Excel) com o conteúdo fornecido."

    # CORRIGIDO: Removido `:folhas_e_conteudo` do schema (que tem default: {}).
    params type: "object",
      properties: {
        path: { type: "string", description: "O caminho e nome do arquivo XLSX a ser criado (ex: 'dados.xlsx')." }
      },
      required: %w[path],
      additionalProperties: false,
      strict: true

    def execute(path:, folhas_e_conteudo: {})
      # 💥 IMPLEMENTAÇÃO DE criar_xlsx
      puts "[XLSX] 📊 Criando arquivo: #{path.inspect}"
      # ... (Assumindo que a lógica de criação do XLSX está em outro lugar ou será implementada aqui)
      return "NotImplemented"
    end
  end

  class InserirConteudoXlsxTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Insere um valor em uma célula específica de um arquivo XLSX existente. A planilha deve ser especificada."

    params do
      string :path, description: "O caminho para o arquivo XLSX."
      string :nome_folha, description: "O nome da folha onde inserir o conteúdo (ex: 'Dados')."
      string :celula, description: "A célula no formato 'A1', 'B2', etc."
      string :valor, description: "O valor a ser inserido na célula."
    end

    def execute(path:, nome_folha:, celula:, valor:)
      # 💥 IMPLEMENTAÇÃO DE inserir_conteudo_xlsx
      puts "[XLSX] ✏️ Inserindo conteúdo em: #{path.inspect}"
      # ... (Assumindo que a lógica de inserção do XLSX está em outro lugar ou será implementada aqui)
      return "NotImplemented"
    end
  end
  


  # ====================================
  # 🧠 Interpretação de Resultados
  # ====================================

  class FsEntregarResultadoTool < RubyLLM::Tool

    extend Forwardable # Use extend para métodos de classe

    # 1. Defina o construtor para receber a instância do Agente
    # Usamos keyword argument `agente_host:` para clareza
    def initialize(agente_host:)
        @agente_host = agente_host
        super() # Chama o construtor pai (se houver)
    end
    
    # 2. Delegue métodos do Agente Host para esta Tool
    # Isso torna `run_ui`, `evaluate`, `shell`, `browser`, etc. acessíveis diretamente
    # como se fossem métodos da OpenUrlTool.
    def_delegators :@agente_host, :run_ui, :ensure_ui_alive, :evaluate
    def_delegators :@agente_host, :shell, :browser, :display, :state, :visible
    description "Ferramenta especial para o LLM. É usada para encerrar uma automação, sinalizando que a tarefa foi concluída e solicitando que o LLM interprete o valor final do processo."

    params do
      string :resultado_final, description: "O valor de saída final da automação. Deve ser uma string que resume o resultado (e.g., o caminho do arquivo gerado, um valor extraído, 'Sucesso', etc.)."
    end

    def execute(resultado_final:)
      puts "[Agent] 🏁 Automação concluída. Resultado: #{resultado_final}"
      resultado_final
    end
  end
end