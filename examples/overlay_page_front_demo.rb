require_relative '../core/framework/glauco-framework'

class OverlayPageFrontDemo < Frontend::Component
  def initialize(**attrs)
    super(**attrs)

    ui do
      div(style: "padding:24px;font-family:Arial,sans-serif;display:flex;flex-direction:column;gap:18px;") do
        h2("Overlay Page declarada no front")

        p("O elemento abaixo existe no HTML da tela e carrega as propriedades da janela overlay via data-*.")

        overlay_page_element(
          id: "youtube_overlay",
          html: <<~HTML,
            <!DOCTYPE html>
            <html>
              <body style="margin:0;height:100vh;display:flex;align-items:center;justify-content:center;background:linear-gradient(135deg,#161616,#3d70b2);color:#fff;font-family:Arial,sans-serif;">
                <div style="padding:32px;border:1px solid rgba(255,255,255,0.25);background:rgba(0,0,0,0.28);box-shadow:0 18px 60px rgba(0,0,0,0.35);">
                  <h1 style="margin:0 0 12px 0;">Overlay shell ativa</h1>
                  <p style="margin:0;">Essa pagina esta sendo renderizada dentro da janela overlay do SWT.</p>
                </div>
              </body>
            </html>
          HTML
          alpha: 245,
          x_ratio: 0.06,
          y_ratio: 0.14,
          width_ratio: 0.88,
          height_ratio: 0.70,
          style: "display:block;padding:16px;border:1px dashed #8d8d8d;background:#f4f4f4;color:#161616;"
        ) do
          div(style: "display:flex;flex-direction:column;gap:8px;") do
            strong("overlay-page")
          end +
          p("Esse nó funciona como elemento declarativo de configuração do shell overlay.") +
          p("Ao clicar no botão, o Ruby lê as propriedades do DOM e abre a janela overlay usando o shell atual.")
        end +
        div(style: "display:flex;gap:12px;align-items:center;") do
          button("Abrir overlay local", onclick: proc {
            Frontend.open_overlay_page_for_element("youtube_overlay")
          }) +
          button("Fechar overlay", onclick: proc {
            Frontend.close_overlay_page
          })
        end +
        p("Dica: mova ou redimensione a janela principal. A overlay acompanha o Browser principal.")
      end
    end
  end
end

app = OverlayPageFrontDemo.new(parent_renderer: $root)
$root.root_component = app
$root.render

$shell.setText("Glauco Overlay Page Front Demo")
$shell.setSize(1320, 900)

Frontend.start!
