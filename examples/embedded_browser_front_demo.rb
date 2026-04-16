require_relative "../core/framework/glauco-framework"

class EmbeddedBrowserFrontDemo < Frontend::Component
  def initialize(**attrs)
    super

    ui do
      div(style: "padding:24px;font-family:Arial,sans-serif;display:flex;flex-direction:column;gap:18px;height:100vh;box-sizing:border-box;background:#f5f7fa;color:#14202b;") do
        [
          div(style: "display:flex;flex-direction:column;gap:8px;max-width:720px;") do
            [
              h2("Embedded Browser Tag"),
              p("Essa view usa um Composite pai no SWT. O elemento abaixo reserva espaço no layout HTML, e o framework encaixa um Browser filho real nessa mesma região da janela.")
            ]
          end,

          div(style: "display:flex;gap:12px;align-items:center;") do
            [
              button("Carregar exemplo.com", onclick: proc {
                Frontend.register_embedded_browser(
                  "embedded_demo_surface",
                  Frontend.embedded_browser_registry["embedded_demo_surface"].merge(url: "https://example.com", html: nil, visible: true)
                )
                Frontend.show_embedded_browser("embedded_demo_surface")
              }),
              button("Carregar HTML local", onclick: proc {
                local_surface_html = %Q{
                  <!DOCTYPE html>
                  <html>
                    <body style="margin:0;font-family:Arial,sans-serif;background:#0f1720;color:#f3f5f7;display:flex;align-items:center;justify-content:center;height:100vh;">
                      <div style="padding:32px;border:1px solid rgba(255,255,255,0.12);border-radius:18px;background:rgba(255,255,255,0.06);max-width:520px;">
                        <h1 style="margin-top:0;">Browser filho embutido</h1>
                        <p>Esta área está sendo renderizada por um Browser SWT filho do Composite pai, não por uma Shell overlay.</p>
                      </div>
                    </body>
                  </html>
                }

                Frontend.register_embedded_browser(
                  "embedded_demo_surface",
                  Frontend.embedded_browser_registry["embedded_demo_surface"].merge(
                    url: nil,
                    html: local_surface_html,
                    visible: true
                  )
                )
                Frontend.show_embedded_browser("embedded_demo_surface")
              }),
              button("Ocultar browser", onclick: proc {
                Frontend.hide_embedded_browser("embedded_demo_surface")
              })
            ]
          end,

          embedded_browser_element(
            id: "embedded_demo_surface",
            visible: true,
            host_content: div(style: "display:flex;align-items:center;justify-content:center;height:100%;color:#4a5a68;font-size:14px;") do
              "Host declarativo do browser filho"
            end,
            style: "display:block;flex:1;min-height:420px;border:1px dashed #8ca0b3;border-radius:18px;background:#dfe7ef;padding:16px;position:relative;overflow:hidden;"
          ) do
            div(style: "margin:0;font-family:Arial,sans-serif;background:#102033;color:#f4f7fb;display:grid;place-items:center;height:100vh;") do
              div(style: "padding:24px 28px;border-radius:16px;background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.1);") do
                strong("Embedded browser surface") +
                  p("O framework vai posicionar um Browser filho SWT exatamente nesta área.")
              end
            end
          end
        ]
      end
    end
  end
end

$root.root_component = EmbeddedBrowserFrontDemo.new(parent_renderer: $root)
$root.render
Frontend.start!
