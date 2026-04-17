# Demo interativa de terminal usando o browser embutido do Glauco Framework.

ENV["GLAUCO_LLM_PROVIDER"] ||= "llama-server"
ENV["GLAUCO_LLAMASERVER_MODEL_KEY"] ||= "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF"
ENV["GLAUCO_LLAMASERVER_IDENTIFIER"] ||= "gemma-4-e4b-it"

require_relative '../core/framework/glauco-framework'

class TerminalSearchBrowserEnv < GlaucoAgentBrowserEnv
  YOUTUBE_OPEN_PATTERN = /\A(?:abra|abrir|abre|pesquise|pesquisar|busque|buscar)\s+(.+?)\s+no\s+youtube\z/i

  def self.capability_schema_definition
    schema = JSON.parse(JSON.generate(super), symbolize_names: true)
    schema[:shell][:capabilities] << capability(
      "youtube_search",
      "Abre uma busca no youtube.",
      params: %w[query]
    )
    schema
  end

  def initialize(visible: true)
    super(visible: visible)
  end

  def youtube_search(query, exclude: nil, **_)
    normalized_query = query.to_s.strip
    raise "query vazia para youtube_search" if normalized_query.empty?
    target_title = js_string_literal(normalized_query)

    open_url("https://www.youtube.com/results?search_query=#{URI.encode_www_form_component(normalized_query)}")
    wait_for_youtube_results!(target_title: target_title)

    eval_js(<<~JS)
      (() => {
        const exact = document.querySelector(`[title=#{target_title}]`);
        if (exact) {
          exact.click();
          return "clicked exact title";
        }

        const firstResult = document.querySelector(
          "ytd-video-renderer a#video-title, a#video-title.yt-simple-endpoint, .yt-simple-endpoint.style-scope.ytd-video-renderer"
        );
        if (firstResult) {
          firstResult.click();
          return "clicked first result";
        }

        return "no clickable result found";
      })()
    JS
  end

  def wait_for_youtube_results!(target_title:, timeout_seconds: 10)
    started_at = Time.now

    loop do
      state = eval_js(<<~JS).to_s
        (() => {
          const currentUrl = String(window.location.href || "");
          const exact = document.querySelector(`[title=#{target_title}]`);
          const firstResult = document.querySelector(
            "ytd-video-renderer a#video-title, a#video-title.yt-simple-endpoint, .yt-simple-endpoint.style-scope.ytd-video-renderer"
          );
          const resultContainer = document.querySelector(
            "ytd-video-renderer, ytd-item-section-renderer, ytd-section-list-renderer, ytd-two-column-search-results-renderer"
          );
          const consentButton = Array.from(document.querySelectorAll("button, tp-yt-paper-button"))
            .find((element) => /accept|agree|concordo|aceitar/i.test((element.innerText || "").trim()));
          return JSON.stringify({
            exact: !!exact,
            firstResult: !!firstResult,
            resultContainer: !!resultContainer,
            consentButton: !!consentButton,
            readyState: document.readyState,
            currentUrl
          });
        })()
      JS

      if state.include?("\"consentButton\":true")
        eval_js(<<~JS)
          (() => {
            const consentButton = Array.from(document.querySelectorAll("button, tp-yt-paper-button"))
              .find((element) => /accept|agree|concordo|aceitar/i.test((element.innerText || "").trim()));
            if (consentButton) {
              consentButton.click();
              return "clicked consent";
            }
            return "no consent button";
          })()
        JS
      end

      return true if state.include?("\"exact\":true") || state.include?("\"firstResult\":true")

      if Time.now - started_at >= timeout_seconds
        raise "timeout esperando resultados do youtube: #{state}"
      end

      sleep 0.5
    end
  end

  def js_string_literal(value)
    value.to_json
  end

  def interpretar(input_text)
    normalized_input = normalize_console_input(input_text)
    youtube_query = extract_youtube_query(normalized_input)
    return youtube_search(youtube_query) if youtube_query

    super(normalized_input)
  end

  def normalize_console_input(input_text)
    input_text.to_s.gsub(/[[:cntrl:]&&[^\n\t]]/, "").strip
  end

  def extract_youtube_query(input_text)
    match = input_text.match(YOUTUBE_OPEN_PATTERN)
    return nil unless match

    query = match[1].to_s.strip
    return nil if query.empty?

    query
  end

end

agent = TerminalSearchBrowserEnv.new(visible: true)

def banner(title)
  puts "\n" + "=" * 80
  puts "TESTE: #{title}"
  puts "=" * 80
end

def safe_exec(agent, input)
  normalized_input = input.to_s.gsub(/[[:cntrl:]&&[^\n\t]]/, "").strip
  puts "\n[Test] Entrada: #{normalized_input.inspect}"
  result = agent.interpretar(normalized_input)
  puts "[Test] Resultado: #{result.inspect}"
rescue => e
  puts "[Test] 💥 Erro: #{e.class} - #{e.message}"
end

banner('MODO CONSOLE INTERATIVO COM BROWSER')

puts "Digite comandos de automação (ex: 'abrir google.com')"
puts "O browser embutido do GlaucoAgentBrowserEnv sera aberto para navegar."
puts "Exemplo de busca com capability: 'pesquise por framework ruby swt'"
puts "Digite 'exit' ou 'sair' para encerrar.\n\n"

loop do
  print '>> '
  input = STDIN.gets&.strip&.dup
  break if input.nil? || input.downcase == 'exit' || input.downcase == 'sair'

  if input.empty?
    puts '[Console] ⚠️ Entrada vazia ignorada.'
    next
  end

  puts input.frozen?
  safe_exec(agent, input)
  puts input.frozen?
end

puts '[Console] ✅ Sessão encerrada.'
