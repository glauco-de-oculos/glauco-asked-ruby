require_relative '../core/framework/glauco-framework'

include Frontend

class StateEffectsDemo < Frontend::Component
  def initialize(parent_renderer:)
    super(parent_renderer: parent_renderer)

    @state[:filters] = {
      status: "Draft",
      owner: "Ana",
      channel: "Email"
    }
    @state[:selected_id] = 101
    @state[:summary] = ""
    @state[:activity] = []

    effect([:filters, :selected_id]) do |filters, selected_id|
      summary = if filters[:only]
        "Campanha ##{selected_id} | replace total aplicado | marcador: #{filters[:only]}"
      else
        "Campanha ##{selected_id} | status: #{filters[:status]} | owner: #{filters[:owner]} | canal: #{filters[:channel]}"
      end

      set_state(:summary, summary)
    end

    effect([:filters, :selected_id], immediate: false, run_on_init: false) do |filters, selected_id|
      entry = "#{Time.now.strftime('%H:%M:%S')} -> commit aplicado para ##{selected_id} com #{filters.inspect}"
      set_state(:activity, [entry] + Array(@state[:activity]).first(7))
    end

    ui do
      css = <<~CSS
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

      script("window.tailwind = window.tailwind || {}; tailwind.config = { theme: { extend: { colors: { ink: '#08111f', mist: '#d7e7f7', pulse: '#78a9ff', glow: '#a7f3d0' } } } };") +
        script(src: "https://cdn.tailwindcss.com") +
        style(css) +
          div(class: "min-h-screen bg-slate-950 text-slate-100") do
            div(class: "mx-auto max-w-7xl px-6 py-8 lg:px-10") do
              div(class: "mb-8 flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between") do
                div do
                  div("Glauco State Runtime", class: "mb-3 text-xs font-semibold uppercase tracking-[0.35em] text-sky-300") +
                    h1("Partial Updates + Multi-Dep Effects", class: "max-w-3xl text-4xl font-semibold tracking-tight text-white lg:text-6xl") +
                    p(class: "mt-4 max-w-3xl text-base leading-7 text-slate-300 lg:text-lg") do
                      "Demo do novo runtime de estado com " +
                        code("set_state") +
                        ", merge parcial raso, " +
                        code("replace: true") +
                        ", " +
                        code("effect([:filters, :selected_id])") +
                        " e execucao pos-commit com " +
                        code("immediate: false") +
                        "."
                    end
                end +
                  inline_notification(
                    kind: "info",
                    open: true,
                    low_contrast: true,
                    title: "Visual atualizado",
                    subtitle: "Layout com utilitarios Tailwind e componentes Carbon."
                  )
              end +
                div(class: "grid gap-6 lg:grid-cols-12") do
                  div(class: "lg:col-span-8") do
                    tile(class: "block rounded-3xl border border-white/10 bg-white/5 p-6 shadow-2xl shadow-slate-950/40 backdrop-blur") do
                      div(class: "mb-6 flex flex-wrap items-start justify-between gap-4") do
                        div do
                          div("Current State", class: "text-xs font-medium uppercase tracking-[0.28em] text-slate-400") +
                            h2("Bindings driven by partial state", class: "mt-2 text-2xl font-semibold text-white")
                        end +
                          div(class: "flex flex-wrap gap-2") do
                            tag("effect", kind: "cyan") +
                              tag("partial merge", kind: "blue") +
                              tag("batch", kind: "green")
                          end
                      end +
                        div(class: "grid gap-4 md:grid-cols-3") do
                          tile(class: "block rounded-2xl bg-slate-900/70 p-5 ring-1 ring-white/10") do
                            div("Selected", class: "text-xs uppercase tracking-[0.25em] text-slate-400") +
                              bind(:selected_id, div(class: "mt-3 text-4xl font-semibold text-white")) { |selected_id| selected_id.to_s }
                          end +
                            tile(class: "block rounded-2xl bg-slate-900/70 p-5 ring-1 ring-white/10") do
                              div("Owner", class: "text-xs uppercase tracking-[0.25em] text-slate-400") +
                                bind(:filters, div(class: "mt-3 text-4xl font-semibold text-cyan-200")) do |filters|
                                  (filters[:owner] || "n/a").to_s
                                end
                            end +
                            tile(class: "block rounded-2xl bg-slate-900/70 p-5 ring-1 ring-white/10") do
                              div("Status", class: "text-xs uppercase tracking-[0.25em] text-slate-400") +
                                bind(:filters, div(class: "mt-3 text-4xl font-semibold text-emerald-200")) do |filters|
                                  (filters[:status] || "replaced").to_s
                                end
                            end
                        end +
                        div(class: "mt-6 rounded-2xl bg-slate-900/70 p-5 ring-1 ring-white/10") do
                          div("Summary effect", class: "text-xs uppercase tracking-[0.25em] text-slate-400") +
                            bind(:summary, div(class: "mt-3 text-lg leading-8 text-slate-100")) { |summary| summary.to_s }
                        end
                    end +
                      tile(class: "mt-6 block rounded-3xl border border-white/10 bg-white/5 p-6 shadow-2xl shadow-slate-950/40 backdrop-blur") do
                        div(class: "mb-4 flex items-center justify-between gap-4") do
                          div do
                            div("Mutations", class: "text-xs uppercase tracking-[0.25em] text-slate-400") +
                              h3("Trigger state updates", class: "mt-2 text-2xl font-semibold text-white")
                          end +
                            tag("Carbon buttons", kind: "purple")
                        end +
                          p(class: "max-w-2xl text-sm leading-6 text-slate-300") do
                            "Cada acao abaixo atualiza apenas parte de " +
                              code(":filters") +
                              ", exceto o replace total. O batch demonstra um unico effect pos-commit mesmo com multiplas mutacoes."
                          end +
                          div(class: "mt-6 flex flex-wrap gap-3") do
                            button(kind: "primary", onclick: proc { set_state(:filters, { status: "Review" }) }) { "Status -> Review" } +
                              button(kind: "secondary", onclick: proc { set_state(:filters, { owner: "Bruno" }) }) { "Owner -> Bruno" } +
                              button(kind: "tertiary", onclick: proc { set_state(:filters, { channel: "Social" }) }) { "Channel -> Social" } +
                              button(kind: "ghost", onclick: proc { set_state(:filters, { status: "Live", owner: "Carla" }) }) { "Merge 2 campos" } +
                              button(kind: "danger--tertiary", onclick: proc { set_state(:filters, { only: "clean-slate" }, replace: true) }) { "Replace total" } +
                              button(
                                kind: "primary",
                                onclick: proc {
                                  batch do
                                    set_state(:selected_id, 202)
                                    set_state(:filters, { status: "Approved", owner: "Dora", channel: "Push" })
                                  end
                                }
                              ) { "Aplicar batch" }
                          end
                      end
                  end +
                    div(class: "lg:col-span-4") do
                      tile(class: "block rounded-3xl border border-white/10 bg-white/5 p-6 shadow-2xl shadow-slate-950/40 backdrop-blur") do
                        div("Current Filters", class: "text-xs uppercase tracking-[0.25em] text-slate-400") +
                          h3("Bound tags", class: "mt-2 text-2xl font-semibold text-white") +
                          bind(:filters, div(class: "mt-5 flex flex-wrap gap-2")) do |filters|
                            filters.map do |key, value|
                              tag("#{key}: #{value}", kind: "teal")
                            end
                          end
                      end +
                        tile(class: "mt-6 block rounded-3xl border border-white/10 bg-white/5 p-6 shadow-2xl shadow-slate-950/40 backdrop-blur") do
                          div("Commit Feed", class: "text-xs uppercase tracking-[0.25em] text-slate-400") +
                            h3("immediate: false", class: "mt-2 text-2xl font-semibold text-white") +
                            bind(:activity, div(class: "mt-5 space-y-3")) do |entries|
                              next inline_notification(
                                kind: "info",
                                open: true,
                                low_contrast: true,
                                title: "Sem commits",
                                subtitle: "Use o batch para gerar o primeiro evento."
                              ) if entries.nil? || entries.empty?

                              entries.map do |entry|
                                tile(class: "block rounded-2xl bg-slate-900/70 p-4 ring-1 ring-white/10") do
                                  div(entry, class: "text-sm leading-6 text-slate-200")
                                end
                              end
                            end
                        end
                    end
                end
            end
        end
    end
  end
end

app = StateEffectsDemo.new(parent_renderer: $root)
$root.root_component = app
$root.render

$shell.setSize(1440, 960)

Frontend::start!
