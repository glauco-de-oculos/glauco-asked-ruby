require_relative '../core/framework/glauco-framework'

include Frontend

class FloatingChatRuntime
  def app_name(*)
    "Glauco Framework"
  end

  def app_summary(*)
    "Aplicacao desktop com interface principal e chat flutuante para onboarding, suporte e vendas."
  end

  def quick_actions(*)
    [
      "Quero ver os planos disponiveis",
      "Como funciona a implantacao?",
      "Preciso falar com vendas",
      "Mostre um resumo do produto"
    ]
  end

  def recommended_next_step(topic = nil, *)
    base =
      case topic.to_s.downcase
      when /venda/
        "Oferecer demonstracao com contexto da conversa."
      when /implant/
        "Explicar etapas de configuracao, integracao e publicacao."
      when /suporte/
        "Guiar a pessoa por um passo a passo objetivo."
      else
        "Conduzir a conversa para o proximo passo util."
      end

    "Proximo passo recomendado: #{base}"
  end
end

class FloatingChatAgent < GlaucoBasicPlasticAgent
  SYSTEM_CONFIG_PATH = File.expand_path("floating_chat_system.md", __dir__)

  def initialize
    super()

    runtime = build_chat_runtime
    bootstrap_agent!(
      system_config_instructions: SYSTEM_CONFIG_PATH,
      runtime: runtime
    )
  end

  def build_chat_runtime
    FloatingChatRuntime.new
  end
end

class FloatingChatApp < Frontend::Component
  QUICK_ACTIONS = [
    "Quero ver os planos disponiveis",
    "Como funciona a implantacao?",
    "Preciso falar com vendas",
    "Mostre um resumo do produto"
  ].freeze

  def initialize(parent_renderer:)
    super(parent_renderer: parent_renderer)

    @chat_agent = FloatingChatAgent.new
    @state[:chat_open] = false
    @state[:chat_draft] = ""
    @state[:typing] = false
    @state[:unread_count] = 1
    @state[:messages] = [
      {
        role: :assistant,
        author: "Glauco AI",
        text: "Oi! Posso te ajudar a encontrar o melhor fluxo para sua operacao.",
        time: "agora"
      }
    ]
    @state[:chat_feed] = {
      messages: @state[:messages],
      typing: @state[:typing]
    }

    ui do
      script("window.tailwind = window.tailwind || {}; tailwind.config = { theme: { extend: { boxShadow: { hero: '0 35px 120px rgba(15, 23, 42, 0.38)', chat: '0 24px 70px rgba(15, 23, 42, 0.32)' } } } };") +
        script(src: "https://cdn.tailwindcss.com") +
        style(base_css) +
        div(class: "min-h-screen bg-[radial-gradient(circle_at_top,_rgba(56,189,248,0.18),_transparent_32%),linear-gradient(180deg,_#f8fafc_0%,_#e2e8f0_48%,_#dbeafe_100%)] text-slate-900") do
          render_shell +
            render_chat_launcher +
            render_chat_panel
        end
    end
  end

  def render_shell
    div(class: "mx-auto flex min-h-screen w-full max-w-7xl flex-col px-6 py-8 lg:px-10") do
      render_nav +
        render_hero +
        render_metrics +
        render_feature_grid
    end
  end

  def render_nav
    div(class: "mb-10 flex items-center justify-between rounded-full border border-white/60 bg-white/70 px-5 py-4 shadow-lg shadow-slate-200/60 backdrop-blur") do
      div(class: "flex items-center gap-3") do
        div("G", class: "flex h-11 w-11 items-center justify-center rounded-2xl bg-sky-500 text-lg font-bold text-white") +
          div do
            div("Glauco Framework", class: "text-sm font-semibold tracking-[0.2em] text-slate-500 uppercase") +
              div("Workspace com assistente flutuante", class: "text-lg font-semibold text-slate-900")
          end
      end +
        div(class: "hidden items-center gap-3 md:flex") do
          button(kind: "ghost", onclick: proc { toggle_chat(true) }) { "Abrir chat" } +
            button(kind: "primary", onclick: proc { push_user_message("Quero agendar uma demonstracao") }) { "Pedir demo" }
        end
    end
  end

  def render_hero
    div(class: "grid gap-8 lg:grid-cols-[1.2fr_0.8fr] lg:items-center") do
      div do
        div("Nova interface", class: "mb-4 inline-flex rounded-full border border-sky-200 bg-sky-50 px-4 py-2 text-xs font-semibold uppercase tracking-[0.3em] text-sky-700") +
          h1("Aplicacao em Glauco com chat flutuante na interface", class: "max-w-4xl text-5xl font-semibold tracking-tight text-slate-950 lg:text-7xl") +
          p(class: "mt-5 max-w-2xl text-lg leading-8 text-slate-600") do
            "Uma tela principal pronta para produto, onboarding ou atendimento, com assistente contextual sempre acessivel no canto da experiencia."
          end +
          div(class: "mt-8 flex flex-wrap gap-3") do
            button(kind: "primary", onclick: proc { toggle_chat(true) }) { "Conversar agora" } +
              button(kind: "secondary", onclick: proc { push_user_message("Mostre um resumo do produto") }) { "Ver resumo guiado" }
          end
      end +
        tile(class: "block rounded-[32px] border border-white/70 bg-white/75 p-6 shadow-hero backdrop-blur-xl") do
          div(class: "mb-6 flex items-center justify-between") do
            div do
              div("Painel ativo", class: "text-xs uppercase tracking-[0.28em] text-slate-400") +
                h2("Resumo operacional", class: "mt-2 text-2xl font-semibold text-slate-900")
            end +
              div("Chat pronto", class: "rounded-full bg-emerald-100 px-4 py-2 text-xs font-semibold uppercase tracking-[0.24em] text-emerald-700")
          end +
            div(class: "grid gap-4 sm:grid-cols-2") do
              insight_card("Assistente persistente", "Atendimento no canto da tela sem interromper o fluxo principal.") +
                insight_card("Estado reativo", "Mensagens, digitacao e badge atualizam sem trocar de pagina.") +
                insight_card("Acionadores rapidos", "Botoes sugerem perguntas e aceleram conversas.") +
                insight_card("Visual de produto", "Layout pronto para SaaS, portal interno ou demo comercial.")
            end
        end
    end
  end

  def render_metrics
    div(class: "mt-10 grid gap-4 md:grid-cols-3") do
      metric_card("Tempo para primeira resposta", "menos de 10s", "Assistente sempre visivel para acelerar discovery.") +
        metric_card("Fluxos sugeridos", QUICK_ACTIONS.length.to_s, "Atalhos prontos para onboarding, vendas e suporte.") +
        metric_card("Modo de entrega", "Flutuante", "Chat sobreposto sem roubar a area principal da interface.")
    end
  end

  def render_feature_grid
    div(class: "mt-10 grid gap-6 xl:grid-cols-[0.95fr_1.05fr]") do
      tile(class: "block rounded-[30px] border border-white/70 bg-slate-950 p-7 text-white shadow-hero") do
        div("Experiencia", class: "text-xs uppercase tracking-[0.28em] text-sky-300") +
          h2("Assistente contextual para qualquer tela do produto", class: "mt-3 max-w-xl text-3xl font-semibold") +
          p(class: "mt-4 max-w-2xl text-base leading-7 text-slate-300") do
            "Use o mesmo componente para suporte, vendas, onboarding, consulta de dados ou copiloto interno. O chat acompanha a jornada sem exigir troca de pagina."
          end +
          div(class: "mt-6 space-y-4") do
            feature_row("Atendimento contextual", "Abre sobre a interface atual e preserva o foco da pessoa usuaria.") +
              feature_row("Integra com estado da tela", "Pode sugerir proximas acoes com base no momento do fluxo.") +
              feature_row("Pronto para backend real", "Hoje com respostas simuladas; depois, basta conectar sua API.")
          end
      end +
        tile(class: "block rounded-[30px] border border-white/70 bg-white/80 p-7 shadow-hero backdrop-blur") do
          div("Acoes rapidas", class: "text-xs uppercase tracking-[0.28em] text-slate-400") +
            h2("Dispare conversas de dentro da propria UI", class: "mt-3 text-3xl font-semibold text-slate-950") +
            p(class: "mt-4 text-base leading-7 text-slate-600") do
              "Esses cards simulam entradas de funil e mostram como o chat flutuante pode ser chamado por qualquer bloco da pagina."
            end +
            div(class: "mt-6 grid gap-4 md:grid-cols-2") do
              action_tile("Onboarding guiado", "Receba passos iniciais para configurar o ambiente.", "Quero ajuda para comecar") +
                action_tile("Plano ideal", "Entenda qual pacote combina com sua operacao.", "Qual plano voce recomenda?") +
                action_tile("Falar com vendas", "Solicite contato humano com contexto da conversa.", "Preciso falar com vendas") +
                action_tile("Resumo executivo", "Veja uma explicacao curta sobre a proposta do produto.", "Mostre um resumo do produto")
            end
        end
    end
  end

  def render_chat_launcher
    bind(:unread_count, div(class: "fixed bottom-6 right-6 z-40")) do |unread_count|
      badge =
        if unread_count.to_i > 0 && !@state[:chat_open]
          div(unread_count.to_s, class: "absolute -top-2 -right-2 flex h-7 min-w-7 items-center justify-center rounded-full bg-rose-500 px-2 text-xs font-bold text-white shadow-lg")
        else
          ""
        end

      button(
        class: "relative flex h-16 w-16 items-center justify-center rounded-full border-0 bg-sky-500 text-2xl font-semibold text-white shadow-chat transition hover:bg-sky-400",
        onclick: proc { toggle_chat(!@state[:chat_open]) }
      ) { "?" } + badge
    end
  end

  def render_chat_panel
    bind(:chat_open, div) do |chat_open|
      next "" unless chat_open

      div(class: "fixed bottom-28 right-6 z-50 w-[min(92vw,420px)]") do
        tile(class: "block overflow-hidden rounded-[28px] border border-white/80 bg-white/92 shadow-chat backdrop-blur-xl") do
          render_chat_header +
            render_chat_messages +
            render_chat_quick_actions +
            render_chat_composer
        end
      end
    end
  end

  def render_chat_header
    div(class: "flex items-start justify-between gap-4 border-b border-slate-200 px-5 py-4") do
      div do
        div("Assistente", class: "text-xs uppercase tracking-[0.28em] text-slate-400") +
          h3("Chat flutuante", class: "mt-1 text-xl font-semibold text-slate-950") +
          p("Atendido por um agent RLM do GlaucoLLM.", class: "mt-1 text-sm text-slate-500")
      end +
        button(kind: "ghost", onclick: proc { toggle_chat(false) }) { "Fechar" }
    end
  end

  def render_chat_messages
    bind(:chat_feed, div(class: "max-h-[360px] space-y-3 overflow-y-auto px-5 py-4", id: "chat-messages")) do |chat_feed|
      items = Array(chat_feed[:messages]).map { |message| message_bubble(message) }
      items << typing_indicator if chat_feed[:typing]
      items
    end
  end

  def render_chat_quick_actions
    div(class: "border-t border-slate-200 px-5 py-4") do
      div("Sugestoes", class: "mb-3 text-xs uppercase tracking-[0.24em] text-slate-400") +
        div(class: "flex flex-wrap gap-2") do
          QUICK_ACTIONS.map do |prompt|
            button(kind: "ghost", onclick: proc { push_user_message(prompt) }) { prompt }
          end
        end
    end
  end

  def render_chat_composer
    div(class: "border-t border-slate-200 px-5 py-4") do
      div(class: "rounded-[24px] bg-slate-100 p-3") do
        textarea(
          "",
          id: "chat-draft",
          rows: "3",
          placeholder: "Digite sua pergunta aqui...",
          oninput: proc { |value| set_state(:chat_draft, value.to_s) },
          class: "w-full resize-none border-0 bg-transparent text-sm leading-6 text-slate-700 outline-none"
        ) +
          div(class: "mt-3 flex items-center justify-between gap-3") do
            p("Mensagem enviada para o agent RLM local.", class: "text-xs text-slate-500") +
              button(kind: "primary", onclick: proc { submit_chat }) { "Enviar" }
          end
      end
    end
  end

  def insight_card(title, body)
    tile(class: "block rounded-[24px] bg-slate-50 p-5 ring-1 ring-slate-200") do
      div(title, class: "text-lg font-semibold text-slate-950") +
        p(body, class: "mt-3 text-sm leading-6 text-slate-600")
    end
  end

  def metric_card(label, value, body)
    tile(class: "block rounded-[26px] border border-white/70 bg-white/75 p-6 shadow-lg shadow-slate-200/60 backdrop-blur") do
      div(label, class: "text-xs uppercase tracking-[0.28em] text-slate-400") +
        div(value, class: "mt-3 text-4xl font-semibold text-slate-950") +
        p(body, class: "mt-3 text-sm leading-6 text-slate-600")
    end
  end

  def feature_row(title, body)
    div(class: "rounded-[24px] border border-white/10 bg-white/5 p-4") do
      div(title, class: "text-lg font-semibold text-white") +
        p(body, class: "mt-2 text-sm leading-6 text-slate-300")
    end
  end

  def action_tile(title, body, prompt)
    tile(class: "block rounded-[24px] border border-slate-200 bg-slate-50 p-5") do
      div(title, class: "text-lg font-semibold text-slate-950") +
        p(body, class: "mt-2 text-sm leading-6 text-slate-600") +
        div(class: "mt-5") do
          button(kind: "secondary", onclick: proc { push_user_message(prompt) }) { "Acionar chat" }
        end
    end
  end

  def message_bubble(message)
    wrapper_class =
      if message[:role] == :user
        "flex justify-end"
      else
        "flex justify-start"
      end

    bubble_class =
      if message[:role] == :user
        "max-w-[85%] rounded-[24px] rounded-br-md bg-sky-500 px-4 py-3 text-sm leading-6 text-white"
      else
        "max-w-[85%] rounded-[24px] rounded-bl-md bg-slate-100 px-4 py-3 text-sm leading-6 text-slate-700"
      end

    div(class: wrapper_class) do
      div(class: bubble_class) do
        div(message[:author], class: "text-[11px] font-semibold uppercase tracking-[0.2em] #{message[:role] == :user ? 'text-sky-100' : 'text-slate-400'}") +
          div(message[:text], class: "mt-2") +
          div(message[:time], class: "mt-2 text-[11px] #{message[:role] == :user ? 'text-sky-100/80' : 'text-slate-400'}")
      end
    end
  end

  def typing_indicator
    div(class: "flex justify-start") do
      div(class: "rounded-[24px] rounded-bl-md bg-slate-100 px-4 py-3 text-sm text-slate-500") do
        "Glauco AI esta digitando..."
      end
    end
  end

  def toggle_chat(open)
    batch do
      set_state(:chat_open, open)
      set_state(:unread_count, 0) if open
    end
    scroll_chat_to_bottom if open
    nil
  end

  def submit_chat
    prompt = @state[:chat_draft].to_s.strip
    return nil if prompt.empty?

    push_user_message(prompt)
    nil
  end

  def push_user_message(prompt)
    now = Time.now.strftime("%H:%M")
    next_messages = Array(@state[:messages]) + [
      {
        role: :user,
        author: "Voce",
        text: prompt,
        time: now
      }
    ]

    batch do
      set_state(:messages, next_messages, replace: true)
      set_state(:chat_draft, "", replace: true)
      set_state(:chat_open, true)
      set_state(:typing, true)
      set_state(:chat_feed, { messages: next_messages, typing: true }, replace: true)
      set_state(:unread_count, 0)
    end

    clear_chat_input
    scroll_chat_to_bottom

    Thread.new do
      response = ask_rlm(prompt)

      async do
        append_assistant_message(response)
      end
    end

    nil
  end

  def ask_rlm(prompt)
    @chat_agent.interpretar(prompt).to_s
  rescue => e
    "Nao consegui consultar o agent em #{GlaucoBasicPlasticAgent::DEFAULT_ENDPOINT}. Detalhe: #{e.message}"
  end

  def append_assistant_message(response)
    updated_messages = Array(@state[:messages]) + [
      {
        role: :assistant,
        author: "Glauco AI",
        text: response,
        time: Time.now.strftime("%H:%M")
      }
    ]

    batch do
      set_state(:messages, updated_messages, replace: true)
      set_state(:typing, false)
      set_state(:chat_feed, { messages: updated_messages, typing: false }, replace: true)
    end

    scroll_chat_to_bottom
  end

  def clear_chat_input
    run_js(<<~JS)
      (() => {
        const field = document.getElementById('chat-draft');
        if (field) field.value = '';
      })();
    JS
  end

  def scroll_chat_to_bottom
    run_js(<<~JS)
      (() => {
        const list = document.getElementById('chat-messages');
        if (list) list.scrollTop = list.scrollHeight;
      })();
    JS
  end

  def base_css
    <<~CSS
      body {
        font-family: "Segoe UI", sans-serif;
      }

      cds-tile::part(base) {
        border-radius: inherit;
        background: transparent;
      }

      cds-button::part(button) {
        min-height: 2.8rem;
        border-radius: 999px;
      }

      textarea:focus {
        outline: none;
      }
    CSS
  end
end

app = FloatingChatApp.new(parent_renderer: $root)
$root.root_component = app
$root.render

$shell.setSize(1480, 920)

Frontend::start!
