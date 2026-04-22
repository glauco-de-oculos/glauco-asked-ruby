require_relative "../core/framework/glauco-framework"

include Frontend

class AgentBehaviorRuntime
  attr_reader :draft

  def initialize
    @draft = {}
  end

  def behavior_templates(*)
    {
      office_ops: "Agente administrativo que organiza arquivos, planilhas, prazos e registros.",
      finance_ops: "Agente financeiro que confere planilhas, consolida dados e aponta inconsistencias.",
      support_ops: "Agente de suporte que conduz atendimento, triagem e proximos passos.",
      sales_ops: "Agente comercial que qualifica demanda, resume contexto e prepara encaminhamento."
    }
  end

  def framework_surface(*)
    "Use Glauco Framework com estado reativo, callbacks Ruby no frontend, set_state, async e runtime methods."
  end

  def save_behavior_blueprint(name:, objective:, tone:, rules:, capabilities:, first_message:)
    @draft = {
      name: name.to_s.strip,
      objective: objective.to_s.strip,
      tone: tone.to_s.strip,
      rules: Array(rules).map(&:to_s),
      capabilities: Array(capabilities).map(&:to_s),
      first_message: first_message.to_s.strip
    }
    nil
  end

  def current_blueprint(*)
    @draft
  end
end

class AgentBehaviorDesignerAgent < GlaucoBasicPlasticAgent
  SYSTEM_CONFIG_PATH = File.expand_path("agent_behavior_system.md", __dir__)

  def initialize(runtime:)
    super()
    bootstrap_agent!(
      system_config_instructions: SYSTEM_CONFIG_PATH,
      runtime: runtime
    )
  end
end

class AgentBehaviorStudio < Frontend::Component
  QUICK_PROMPTS = [
    "Crie um comportamento para organizar documentos e planilhas",
    "Transforme isso em prompt de sistema curto",
    "Adicione limites de seguranca e confirmacao antes de alterar arquivos",
    "Sugira funcoes runtime para conectar back to front"
  ].freeze

  def initialize(parent_renderer:)
    super(parent_renderer: parent_renderer)

    @runtime = AgentBehaviorRuntime.new
    @agent = nil

    @state[:agent_name] = "Pacioli Ops Agent"
    @state[:objective] = "Ajudar usuarios a formular, revisar e executar rotinas administrativas com arquivos e planilhas."
    @state[:tone] = "Claro, objetivo e cuidadoso."
    @state[:capabilities] = "listar arquivos, ler documentos, editar planilhas, criar registros, comparar versoes"
    @state[:boundaries] = "Confirmar antes de mover, apagar ou sobrescrever arquivos. Nunca inventar caminhos."
    @state[:chat_draft] = ""
    @state[:messages] = initial_messages
    @state[:chat_feed] = { messages: @state[:messages], typing: false }
    @state[:typing] = false
    @state[:error] = nil
    @state[:spec_preview] = build_spec_preview

    ui do
      script("window.tailwind = window.tailwind || {}; tailwind.config = { theme: { extend: { boxShadow: { work: '0 24px 60px rgba(15, 23, 42, 0.18)' } } } };") +
        script(src: "https://cdn.tailwindcss.com") +
        style(base_css) +
        div(class: "min-h-screen bg-[#f4f4f4] text-[#161616]") do
          div(class: "mx-auto flex min-h-screen max-w-[1520px] flex-col px-5 py-5 lg:px-8") do
            render_header +
              bind(:error, div) do |error|
                next "" if error.to_s.empty?

                inline_notification(
                  kind: "error",
                  open: true,
                  low_contrast: true,
                  title: "Falha no agente",
                  subtitle: error.to_s
                )
              end +
              div(class: "grid flex-1 gap-5 xl:grid-cols-[420px_1fr_460px]") do
                render_behavior_form +
                  render_spec_panel +
                  render_chatbox
              end
          end
        end
    end
  end

  def initial_messages
    [
      {
        role: :assistant,
        author: "Designer",
        text: "Descreva o comportamento do agente. Eu devolvo um rascunho pronto para usar no Glauco Framework.",
        time: "agora"
      }
    ]
  end

  def render_header
    div(class: "mb-5 flex flex-col gap-3 border-b border-[#d0d0d0] pb-4 lg:flex-row lg:items-end lg:justify-between") do
      div do
        div("Pacioli Production", class: "text-xs font-semibold uppercase tracking-[0.28em] text-[#525252]") +
          h1("Criacao de agente", class: "mt-2 text-3xl font-semibold tracking-tight lg:text-5xl") +
          p("Formule comportamento, limites e funcoes de runtime com um chatbox conectado ao backend Ruby.", class: "mt-2 max-w-3xl text-sm leading-6 text-[#525252]")
      end +
        div(class: "flex flex-wrap gap-2") do
          button(kind: "secondary", onclick: proc { refresh_spec_preview }) { "Atualizar preview" } +
            button(kind: "ghost", onclick: proc { reset_workspace }) { "Limpar" }
        end
    end
  end

  def render_behavior_form
    section(class: "min-h-0 border border-[#d0d0d0] bg-white p-4 shadow-work") do
      div("Briefing", class: "text-xs font-semibold uppercase tracking-[0.24em] text-[#525252]") +
        h2("Entrada do comportamento", class: "mt-2 text-xl font-semibold") +
        div(class: "mt-5 space-y-4") do
          field_textarea("Nome", :agent_name, 2, "Nome do agente") +
            field_textarea("Objetivo", :objective, 5, "O que o agente deve fazer") +
            field_textarea("Tom", :tone, 3, "Como ele deve falar") +
            field_textarea("Capacidades", :capabilities, 5, "Funcoes, ferramentas ou acoes permitidas") +
            field_textarea("Limites", :boundaries, 5, "Regras de seguranca e confirmacao")
        end
    end
  end

  def render_spec_panel
    section(class: "min-h-0 border border-[#d0d0d0] bg-white p-4 shadow-work") do
      div(class: "flex items-start justify-between gap-4") do
        div do
          div("Blueprint", class: "text-xs font-semibold uppercase tracking-[0.24em] text-[#525252]") +
            h2("Comportamento em producao", class: "mt-2 text-xl font-semibold")
        end +
          button(kind: "primary", onclick: proc { refresh_spec_preview }) { "Atualizar" }
      end +
        bind(:spec_preview, pre(class: "mt-5 h-[calc(100vh-220px)] overflow-auto whitespace-pre-wrap border border-[#e0e0e0] bg-[#f4f4f4] p-4 font-mono text-sm leading-6 text-[#262626]")) do |preview|
          preview.to_s
        end
    end
  end

  def render_chatbox
    agent_chatbox(
      id: "behavior-chatbox",
      title: "Chatbox",
      subtitle: "Formulador de comportamento com on_input, output_handler e bloco filho reativo.",
      placeholder: "Ex: crie um agente que revise contratos e peca confirmacao antes de alterar arquivos",
      initial_messages: initial_messages,
      quick_prompts: QUICK_PROMPTS,
      user_author: "Voce",
      response_author: "Designer",
      on_input: proc { |_message| set_state(:error, nil, replace: true) },
      output_handler: proc { |message| ask_designer(message) },
      on_response: proc { |response| set_state(:spec_preview, merge_response_into_preview(response), replace: true) },
      class: "shadow-work"
    ) do |handler, outputs|
      messages = Array(outputs[:messages])
      div(class: "flex items-center justify-between gap-3") do
        div do
          div("Slot HTML do componente", class: "text-xs font-semibold uppercase tracking-[0.2em] text-[#525252]") +
            p("#{messages.length} mensagens no output atual.", class: "mt-1 text-sm text-[#525252]")
        end +
          button(kind: "secondary", onclick: proc { handler.call("Gere um blueprint completo com base no briefing atual.") }) do
            "Gerar"
          end
      end
    end
  end

  def field_textarea(label, key, rows, placeholder)
    div do
      label_tag = label(label, class: "mb-2 block text-xs font-semibold uppercase tracking-[0.18em] text-[#525252]")
      input_tag = textarea(
        @state[key].to_s,
        rows: rows.to_s,
        placeholder: placeholder,
        oninput: proc { |value| update_field(key, value.to_s) },
        class: "w-full resize-none border border-[#8d8d8d] bg-[#f4f4f4] p-3 text-sm leading-6 outline-none focus:border-[#0f62fe]"
      )

      label_tag + input_tag
    end
  end

  def update_field(key, value)
    batch do
      set_state(key, value, replace: true)
      set_state(:spec_preview, build_spec_preview(key => value), replace: true)
    end
    nil
  end

  def ask_designer(prompt)
    designer_agent.interpretar(compose_agent_task(prompt)).to_s
  rescue => e
    fallback_behavior_response(prompt, e)
  end

  def designer_agent
    @agent ||= AgentBehaviorDesignerAgent.new(runtime: @runtime)
  end

  def compose_agent_task(prompt)
    <<~TASK
      Pedido do usuario:
      #{prompt}

      Briefing atual:
      Nome: #{@state[:agent_name]}
      Objetivo: #{@state[:objective]}
      Tom: #{@state[:tone]}
      Capacidades: #{@state[:capabilities]}
      Limites: #{@state[:boundaries]}

      Retorne um blueprint de comportamento pronto para colocar na interface.
      Use runtime methods se precisar registrar o blueprint.
    TASK
  end

  def fallback_behavior_response(prompt, error)
    <<~TEXT
      Blueprint gerado localmente porque o LLM nao respondeu: #{error.message}

      Nome: #{@state[:agent_name]}
      Objetivo: #{@state[:objective]}
      Tom: #{@state[:tone]}

      Regras:
      - Confirmar antes de executar acoes destrutivas.
      - Usar caminhos completos ao lidar com arquivos.
      - Explicar o proximo passo em linguagem simples.
      - Quando faltar contexto, pedir a menor informacao necessaria.

      Capacidades:
      #{@state[:capabilities]}

      Pedido tratado:
      #{prompt}
    TEXT
  end

  def merge_response_into_preview(response)
    [build_spec_preview, "", "## Ultima formulacao do chat", response.to_s].join("\n")
  end

  def build_spec_preview(overrides = {})
    values = {
      agent_name: @state[:agent_name],
      objective: @state[:objective],
      tone: @state[:tone],
      capabilities: @state[:capabilities],
      boundaries: @state[:boundaries]
    }.merge(overrides)

    <<~SPEC
      # #{values[:agent_name]}

      ## Objetivo
      #{values[:objective]}

      ## Tom
      #{values[:tone]}

      ## Capacidades
      #{values[:capabilities]}

      ## Limites
      #{values[:boundaries]}

      ## Contrato back-to-front
      - Eventos da UI chamam callbacks Ruby no Frontend::Component.
      - O backend atualiza estado com set_state.
      - Respostas assincronas voltam para a tela com async.
      - run_js e usado apenas para detalhes de DOM como limpar input e rolar o chat.

      ## Esqueleto Glauco
      class #{values[:agent_name].to_s.gsub(/[^A-Za-z0-9]+/, "")} < GlaucoBasicPlasticAgent
        def initialize(runtime:)
          super()
          bootstrap_agent!(
            system_config_instructions: "agent_behavior_system.md",
            runtime: runtime
          )
        end
      end
    SPEC
  end

  def reset_workspace
    batch do
      set_state(:error, nil)
      set_state(:spec_preview, build_spec_preview, replace: true)
    end
    nil
  end

  def refresh_spec_preview
    set_state(:spec_preview, build_spec_preview, replace: true)
    nil
  end

  def base_css
    <<~CSS
      body {
        font-family: "Segoe UI", Arial, sans-serif;
        background: #f4f4f4;
      }

      cds-button::part(button) {
        min-height: 2.5rem;
        border-radius: 0;
      }

      textarea:focus {
        box-shadow: inset 0 0 0 1px #0f62fe;
      }
    CSS
  end
end

app = AgentBehaviorStudio.new(parent_renderer: $root)
$root.root_component = app
$root.render

$shell.setText("Pacioli Production - Agent Behavior Studio")
$shell.setSize(1440, 900)

Frontend.start!
