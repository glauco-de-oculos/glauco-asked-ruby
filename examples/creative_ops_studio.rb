require_relative '../core/framework/glauco-framework'
require_relative './creative_ops_backend'

include Frontend

class CreativeOpsStudio < Frontend::Component
  def initialize(parent_renderer:)
    super(parent_renderer: parent_renderer)

    @state[:filters] = {
      status: "All",
      channel: "All",
      owner: "All"
    }
    @state[:summary] = summarize_campaigns([])
    @state[:campaigns] = []
    @state[:campaign_view] = { items: [], selected_id: nil }
    @state[:selected_id] = nil
    @state[:selected_campaign] = {}
    @state[:timeline] = []
    @state[:alerts] = []
    @state[:activity] = []
    @state[:loading] = true
    @state[:timeline_loading] = false
    @state[:saving] = false
    @state[:error] = nil

    effect([:campaigns, :selected_id], run_on_init: false) do |campaigns, selected_id|
      items = Array(campaigns)
      selected = items.find { |campaign| campaign[:id] == selected_id } || items.first || {}

      batch do
        set_state(:campaign_view, { items: items, selected_id: selected[:id] }, replace: true)
        set_state(:selected_campaign, selected, replace: true)
      end
    end

    effect(:selected_id, run_on_init: false) do |selected_id|
      load_timeline_for(selected_id)
    end

    ui do
      script("window.tailwind = window.tailwind || {}; tailwind.config = { theme: { extend: { boxShadow: { studio: '0 30px 80px rgba(2, 6, 23, 0.45)' } } } };") +
        script(src: "https://cdn.tailwindcss.com") +
        style(base_css) +
        div(class: "min-h-screen bg-slate-950 text-slate-100") do
          div(class: "mx-auto max-w-[1600px] px-6 py-8 lg:px-10") do
            render_header +
              bind(:error, div(class: "mb-6")) do |error|
                next "" if error.nil? || error.to_s.empty?

                inline_notification(
                  kind: "error",
                  open: true,
                  low_contrast: true,
                  title: "Erro do backend local",
                  subtitle: error.to_s
                )
              end +
              bind(:loading, div(class: "mb-6")) do |loading|
                next "" unless loading

                inline_notification(
                  kind: "info",
                  open: true,
                  low_contrast: true,
                  title: "Carregando workspace",
                  subtitle: "Buscando fila, alertas e activity feed do studio."
                )
              end +
              div(class: "grid gap-6 xl:grid-cols-12") do
                div(class: "xl:col-span-8") do
                  render_summary_panel +
                    render_review_panel +
                    render_queue_panel
                end +
                  div(class: "xl:col-span-4") do
                    render_filters_panel +
                      render_alerts_panel +
                      render_timeline_panel +
                      render_activity_panel
                  end
              end
          end
        end
    end

    load_workspace
  end

  def render_header
    div(class: "mb-8 flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between") do
      div do
        div("Creative Ops Studio", class: "mb-3 text-xs font-semibold uppercase tracking-[0.35em] text-sky-300") +
          h1("Dense single-screen workspace for Glauco", class: "max-w-4xl text-4xl font-semibold tracking-tight text-white lg:text-6xl") +
          p(class: "mt-4 max-w-3xl text-base leading-7 text-slate-300 lg:text-lg") do
            "Uma demo de produto ficticio para mostrar filtros, review queue, alerts, activity feed e timeline com estado reativo, backend local e componentes Carbon."
          end
      end +
        div(class: "flex flex-wrap gap-3") do
          button(kind: "secondary", onclick: proc { load_workspace(preserve_selected: @state[:selected_id]) }) { "Refresh workspace" } +
            button(kind: "ghost", onclick: proc { load_workspace(simulate_error: true, preserve_selected: @state[:selected_id]) }) { "Simular erro" }
        end
    end
  end

  def render_summary_panel
    tile(class: "mb-6 block rounded-[28px] border border-white/10 bg-white/5 p-6 shadow-studio backdrop-blur-xl") do
      div(class: "mb-5 flex items-center justify-between gap-4") do
        div do
          div("Overview", class: "text-xs uppercase tracking-[0.28em] text-slate-400") +
            h2("Creative command center", class: "mt-2 text-2xl font-semibold text-white")
        end +
          tag("single-screen app", type: "blue")
      end +
        bind(:summary, div(class: "grid gap-4 md:grid-cols-4")) do |summary|
          [
            summary_card("Visible campaigns", summary[:total].to_s, "text-white"),
            summary_card("In review", summary[:review].to_s, "text-cyan-200"),
            summary_card("Live now", summary[:live].to_s, "text-emerald-200"),
            summary_card("High risk", summary[:risk].to_s, "text-rose-200")
          ]
        end
    end
  end

  def render_review_panel
    tile(class: "mb-6 block rounded-[28px] border border-white/10 bg-white/5 p-6 shadow-studio backdrop-blur-xl") do
      div(class: "mb-5 flex items-center justify-between gap-4") do
        div do
          div("Review board", class: "text-xs uppercase tracking-[0.28em] text-slate-400") +
            h2("Selected campaign", class: "mt-2 text-2xl font-semibold text-white")
        end +
          bind(:saving, div) do |saving|
            next tag("idle", type: "green") unless saving

            tag("saving", type: "purple")
          end
      end +
        bind(:selected_campaign, div) do |campaign|
          next empty_tile("Nenhuma campanha selecionada.", "Ajuste os filtros ou recarregue o workspace.") if campaign.nil? || campaign.empty?

          div(class: "grid gap-5 lg:grid-cols-[1.35fr_0.65fr]") do
            tile(class: "block rounded-[22px] bg-slate-900/70 p-5 ring-1 ring-white/10") do
              div(class: "flex flex-wrap items-start justify-between gap-4") do
                div do
                  div(campaign[:channel], class: "text-xs uppercase tracking-[0.25em] text-slate-400") +
                    h3(campaign[:name], class: "mt-2 text-3xl font-semibold text-white")
                end +
                  div(class: "flex flex-wrap gap-2") do
                    tag(campaign[:status], type: tag_type_for_status(campaign[:status])) +
                      tag("Priority: #{campaign[:priority]}", type: tag_type_for_priority(campaign[:priority]))
                  end
              end +
                p(campaign[:notes], class: "mt-5 max-w-3xl text-base leading-7 text-slate-300") +
                div(class: "mt-6 grid gap-3 sm:grid-cols-3") do
                  metric_block("Owner", campaign[:owner]) +
                    metric_block("Score", campaign[:score].to_s) +
                    metric_block("Due", campaign[:due_in])
                end +
                div(class: "mt-6 flex flex-wrap gap-3") do
                  button(kind: "primary", onclick: proc { save_decision(campaign[:id], :approve) }) { "Approve" } +
                    button(kind: "secondary", onclick: proc { save_decision(campaign[:id], :pause) }) { "Pause" } +
                    button(kind: "ghost", onclick: proc { save_decision(campaign[:id], :flag) }) { "Flag for review" } +
                    button(kind: "danger--tertiary", onclick: proc { save_decision(campaign[:id], :simulate_error) }) { "Simular falha" }
                end
            end +
              tile(class: "block rounded-[22px] bg-slate-900/70 p-5 ring-1 ring-white/10") do
                div("Inspector", class: "text-xs uppercase tracking-[0.25em] text-slate-400") +
                  h3("Selection details", class: "mt-2 text-xl font-semibold text-white") +
                  bind(:filters, div(class: "mt-5 flex flex-wrap gap-2")) do |filters|
                    filters.map do |key, value|
                      tag("#{key}: #{value}", type: "teal")
                    end
                  end +
                  div(class: "mt-6 rounded-2xl bg-white/5 p-4") do
                    div("What changed", class: "text-xs uppercase tracking-[0.2em] text-slate-500") +
                      p(class: "mt-3 text-sm leading-6 text-slate-300") do
                        "A fila responde aos filtros acima, enquanto as decisoes de review atualizam summary, alerts e activity feed sem trocar de tela."
                      end
                  end
              end
          end
        end
    end
  end

  def render_queue_panel
    tile(class: "block rounded-[28px] border border-white/10 bg-white/5 p-6 shadow-studio backdrop-blur-xl") do
      div(class: "mb-5 flex items-center justify-between gap-4") do
        div do
          div("Queue", class: "text-xs uppercase tracking-[0.28em] text-slate-400") +
            h2("Campaign review queue", class: "mt-2 text-2xl font-semibold text-white")
        end +
          tag("interactive list", type: "purple")
      end +
        bind(:campaign_view, div(class: "space-y-4")) do |view|
          items = Array(view[:items])
          selected_id = view[:selected_id]

          next empty_tile("Nenhuma campanha encontrada.", "Troque os filtros para voltar ao fluxo principal.") if items.empty?

          items.map do |campaign|
            selected = campaign[:id] == selected_id
            queue_item(campaign, selected)
          end
        end
    end
  end

  def render_filters_panel
    tile(class: "mb-6 block rounded-[28px] border border-white/10 bg-white/5 p-6 shadow-studio backdrop-blur-xl") do
      div("Filters", class: "text-xs uppercase tracking-[0.28em] text-slate-400") +
        h2("Workspace controls", class: "mt-2 text-2xl font-semibold text-white") +
        bind(:filters, div(class: "mt-5 space-y-5")) do |filters|
          [
            filter_group("Status", %w[All Review Live Paused Draft], filters[:status], :status),
            filter_group("Channel", %w[All Email Social Push], filters[:channel], :channel),
            filter_group("Owner", ["All", "Ana", "Bruno", "Carla", "Dora", "Nobody"], filters[:owner], :owner)
          ]
        end
    end
  end

  def render_alerts_panel
    tile(class: "mb-6 block rounded-[28px] border border-white/10 bg-white/5 p-6 shadow-studio backdrop-blur-xl") do
      div("Alerts", class: "text-xs uppercase tracking-[0.28em] text-slate-400") +
        h2("Creative risk radar", class: "mt-2 text-2xl font-semibold text-white") +
        bind(:alerts, div(class: "mt-5 space-y-3")) do |alerts|
          next empty_tile("Sem alertas ativos.", "A fila esta limpa neste recorte.") if alerts.nil? || alerts.empty?

          alerts.map do |alert|
            inline_notification(
              kind: alert[:kind],
              open: true,
              low_contrast: true,
              title: alert[:title],
              subtitle: alert[:subtitle]
            )
          end
        end
    end
  end

  def render_timeline_panel
    tile(class: "mb-6 block rounded-[28px] border border-white/10 bg-white/5 p-6 shadow-studio backdrop-blur-xl") do
      div("Timeline", class: "text-xs uppercase tracking-[0.28em] text-slate-400") +
        h2("Execution pulse", class: "mt-2 text-2xl font-semibold text-white") +
        bind(:timeline_loading, div(class: "mt-4")) do |loading|
          next "" unless loading

          inline_notification(
            kind: "info",
            open: true,
            low_contrast: true,
            title: "Atualizando timeline",
            subtitle: "Carregando os eventos da campanha selecionada."
          )
        end +
        bind(:timeline, div(class: "mt-5 space-y-3")) do |timeline|
          next empty_tile("Sem eventos para mostrar.", "Selecione uma campanha para ver o contexto.") if timeline.nil? || timeline.empty?

          timeline.map do |event|
            tile(class: "block rounded-[22px] bg-slate-900/70 p-4 ring-1 ring-white/10") do
              div(event, class: "text-sm leading-6 text-slate-200")
            end
          end
        end
    end
  end

  def render_activity_panel
    tile(class: "block rounded-[28px] border border-white/10 bg-white/5 p-6 shadow-studio backdrop-blur-xl") do
      div("Activity feed", class: "text-xs uppercase tracking-[0.28em] text-slate-400") +
        h2("Latest studio moves", class: "mt-2 text-2xl font-semibold text-white") +
        bind(:activity, div(class: "mt-5 space-y-3")) do |entries|
          next empty_tile("Sem atividade recente.", "Aguarde uma acao do studio.") if entries.nil? || entries.empty?

          entries.map do |entry|
            tile(class: "block rounded-[22px] bg-slate-900/70 p-4 ring-1 ring-white/10") do
              div(entry, class: "text-sm leading-6 text-slate-200")
            end
          end
        end
    end
  end

  def filter_group(label, values, selected_value, key)
    div do
      div(label, class: "text-xs uppercase tracking-[0.25em] text-slate-400") +
        div(class: "mt-3 flex flex-wrap gap-2") do
          values.map do |value|
            kind = value == selected_value ? "primary" : "ghost"
            button(kind: kind, onclick: proc { update_filters(key => value) }) { value }
          end
        end
    end
  end

  def queue_item(campaign, selected)
    wrapper_classes = [
      "block rounded-[22px] p-5 ring-1 transition",
      selected ? "bg-sky-500/10 ring-sky-400/40" : "bg-slate-900/70 ring-white/10 hover:bg-slate-900"
    ].join(" ")

    tile(class: wrapper_classes) do
      div(class: "flex flex-wrap items-start justify-between gap-4") do
        div do
          div(campaign[:channel], class: "text-xs uppercase tracking-[0.2em] text-slate-500") +
            h3(campaign[:name], class: "mt-2 text-xl font-semibold text-white") +
            p("Owner: #{campaign[:owner]} | Due: #{campaign[:due_in]}", class: "mt-2 text-sm text-slate-300")
        end +
          div(class: "flex flex-wrap gap-2") do
            tag(campaign[:status], type: tag_type_for_status(campaign[:status])) +
              tag("Score #{campaign[:score]}", type: "cyan")
          end
      end +
        div(class: "mt-5 flex flex-wrap gap-3") do
          button(kind: selected ? "secondary" : "ghost", onclick: proc { select_campaign(campaign[:id]) }) { selected ? "Selected" : "Inspect" } +
            button(kind: "primary", onclick: proc { save_decision(campaign[:id], :approve) }) { "Approve" }
        end
    end
  end

  def summary_card(label, value, value_class)
    tile(class: "block rounded-[22px] bg-slate-900/70 p-5 ring-1 ring-white/10") do
      div(label, class: "text-xs uppercase tracking-[0.25em] text-slate-400") +
        div(value, class: "mt-3 text-4xl font-semibold #{value_class}")
    end
  end

  def metric_block(label, value)
    div(class: "rounded-2xl bg-white/5 p-4") do
      div(label, class: "text-xs uppercase tracking-[0.2em] text-slate-500") +
        div(value, class: "mt-2 text-xl font-semibold text-white")
    end
  end

  def empty_tile(title, subtitle)
    inline_notification(
      kind: "info",
      open: true,
      low_contrast: true,
      title: title,
      subtitle: subtitle
    )
  end

  def tag_type_for_status(status)
    {
      "Review" => "cyan",
      "Live" => "green",
      "Paused" => "red",
      "Draft" => "cool-gray"
    }[status] || "blue"
  end

  def tag_type_for_priority(priority)
    {
      "High" => "red",
      "Medium" => "purple",
      "Low" => "green"
    }[priority] || "blue"
  end

  def base_css
    <<~CSS
      body {
        background: #020617;
      }

      cds-tile::part(base) {
        border-radius: inherit;
      }

      cds-button::part(button) {
        min-height: 3rem;
      }
    CSS
  end

  def update_filters(patch)
    next_filters = @state[:filters].merge(patch)

    batch do
      set_state(:filters, patch)
      set_state(:error, nil)
    end

    load_workspace(preserve_selected: @state[:selected_id], filters_override: next_filters)
    nil
  end

  def select_campaign(campaign_id)
    set_state(:selected_id, campaign_id)
    nil
  end

  def load_workspace(simulate_error: false, preserve_selected: nil, filters_override: nil)
    filters = deep_dup(filters_override || @state[:filters])

    batch do
      set_state(:loading, true)
      set_state(:error, nil)
    end

    Thread.new do
      begin
        campaigns = CreativeOpsBackend.load_campaigns(filters, simulate_error: simulate_error)
        summary = summarize_campaigns(campaigns)
        alerts = CreativeOpsBackend.load_alerts(filters)
        activity = CreativeOpsBackend.load_activity_feed(filters)
        selected_id = choose_selected_id(campaigns, preserve_selected)

        async do
          batch do
            set_state(:summary, summary, replace: true)
            set_state(:campaigns, campaigns, replace: true)
            set_state(:alerts, alerts, replace: true)
            set_state(:activity, activity, replace: true)
            set_state(:selected_id, selected_id, replace: true)
            set_state(:loading, false)
          end
        end
      rescue => e
        async do
          batch do
            set_state(:summary, summarize_campaigns([]), replace: true)
            set_state(:campaigns, [], replace: true)
            set_state(:campaign_view, { items: [], selected_id: nil }, replace: true)
            set_state(:selected_campaign, {}, replace: true)
            set_state(:timeline, [], replace: true)
            set_state(:loading, false)
            set_state(:timeline_loading, false)
            set_state(:selected_id, nil, replace: true)
            set_state(:error, e.message)
          end
        end
      end
    end

    nil
  end

  def load_timeline_for(campaign_id)
    if campaign_id.nil?
      batch do
        set_state(:timeline_loading, false)
        set_state(:timeline, [], replace: true)
      end
      return nil
    end

    set_state(:timeline_loading, true)

    Thread.new do
      timeline = CreativeOpsBackend.load_timeline(campaign_id)

      async do
        batch do
          set_state(:timeline, timeline, replace: true)
          set_state(:timeline_loading, false)
        end
      end
    rescue => e
      async do
        batch do
          set_state(:timeline_loading, false)
          set_state(:error, e.message)
        end
      end
    end

    nil
  end

  def save_decision(campaign_id, action)
    batch do
      set_state(:saving, true)
      set_state(:error, nil)
    end

    Thread.new do
      begin
        result = CreativeOpsBackend.save_review_decision(campaign_id, action)

        async do
          updated_campaigns = Array(@state[:campaigns]).map do |campaign|
            campaign[:id] == campaign_id ? result[:campaign] : campaign
          end
          updated_alerts = result[:alert] ? [result[:alert]] + Array(@state[:alerts]).first(2) : @state[:alerts]
          updated_activity = [result[:activity_entry]] + Array(@state[:activity]).first(5)

          batch do
            set_state(:campaigns, updated_campaigns, replace: true)
            set_state(:summary, summarize_campaigns(updated_campaigns), replace: true)
            set_state(:alerts, updated_alerts, replace: true)
            set_state(:activity, updated_activity, replace: true)
            set_state(:saving, false)
            set_state(:selected_id, campaign_id)
          end
        end
      rescue => e
        async do
          batch do
            set_state(:saving, false)
            set_state(:error, e.message)
          end
        end
      end
    end

    nil
  end

  def choose_selected_id(campaigns, preserve_selected)
    ids = campaigns.map { |campaign| campaign[:id] }
    return preserve_selected if preserve_selected && ids.include?(preserve_selected)

    campaigns.first && campaigns.first[:id]
  end

  def summarize_campaigns(campaigns)
    {
      total: campaigns.length,
      review: campaigns.count { |campaign| campaign[:status] == "Review" },
      live: campaigns.count { |campaign| campaign[:status] == "Live" },
      risk: campaigns.count { |campaign| campaign[:priority] == "High" || campaign[:status] == "Paused" }
    }
  end

  def deep_dup(value)
    Marshal.load(Marshal.dump(value))
  end
end

app = CreativeOpsStudio.new(parent_renderer: $root)
$root.root_component = app
$root.render

$shell.setSize(1560, 980)

Frontend::start!
