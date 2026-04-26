# pacioli-production/whatsapp_web_app.rb

require "fileutils"
require "java"
require "json"
require "net/http"
require "uri"

require_relative "../core/framework/glauco-framework"

include Frontend

java_import "java.lang.System"
java_import "org.eclipse.swt.SWT"
java_import "org.eclipse.swt.widgets.Composite"
java_import "org.eclipse.swt.browser.Browser"
java_import "org.eclipse.swt.layout.FillLayout"
java_import "java.awt.Robot"
java_import "java.awt.event.InputEvent"

# ------------------------------------------------------------
# Perfil persistente do WebView2 / Edge
# ------------------------------------------------------------
#
# Precisa rodar antes de Display.new / Browser.new.
# Como o Frontend.ensure_frontend_runtime! cria o Display e o Browser
# principal do Glauco, esta configuração deve vir antes dele.
#
module GlaucoBrowserProfile
  def self.configure!(profile_name:)
    profile_dir = File.expand_path(
      File.join(Dir.home, ".glauco", "profiles", profile_name, "webview2")
    )

    FileUtils.mkdir_p(profile_dir)

    System.setProperty("org.eclipse.swt.browser.DefaultType", "edge")
    System.setProperty("org.eclipse.swt.browser.EdgeDataDir", profile_dir)

    profile_dir
  end
end

GlaucoBrowserProfile.configure!(profile_name: "whatsapp-web-main")

# ------------------------------------------------------------
# Inicialização do runtime visual Glauco
# ------------------------------------------------------------

Frontend.ensure_frontend_runtime!

$shell.setText("Glauco Framework - WhatsApp Web")
$shell.setSize(1440, 900)

# ------------------------------------------------------------
# Elemento WebContentView
# ------------------------------------------------------------
#
# Este elemento cria um SWT Browser filho dentro do surface_parent.
# A UI principal continua sendo renderizada pelo Glauco no $browser.
# O WhatsApp roda em outro Browser, visualmente posicionado como painel.
#
class WebContentView
  attr_reader :browser, :parent

  def initialize(parent:, url:, x:, y:, width:, height:)
    @parent = parent
    @url = url
    @x = x
    @y = y
    @width = width
    @height = height

    @browser = Browser.new(@parent, SWT::BORDER)
    @browser.setBounds(@x, @y, @width, @height)

    # Ponto essencial:
    # coloca o Browser do WhatsApp acima do Browser principal do Glauco.
    @browser.moveAbove(nil)

    @browser.setVisible(true)
    @browser.setUrl(@url)

    @parent.layout(true)
  end

  def resize(x:, y:, width:, height:)
    @x = x
    @y = y
    @width = width
    @height = height

    return if @browser.isDisposed

    @browser.setBounds(@x, @y, @width, @height)
    @browser.moveAbove(nil)
    @parent.layout(true)
  end

  def navigate(url)
    return if @browser.isDisposed

    @browser.moveAbove(nil)
    @browser.setUrl(url.to_s)
  end

  def reload
    @browser.refresh unless @browser.isDisposed
  end

  def back
    @browser.back if !@browser.isDisposed && @browser.isBackEnabled
  end

  def forward
    @browser.forward if !@browser.isDisposed && @browser.isForwardEnabled
  end

  def dispose
    @browser.dispose unless @browser.isDisposed
  end
end

# ------------------------------------------------------------
# Componente principal
# ------------------------------------------------------------

class WhatsAppWebStudio < Frontend::Component
  def initialize(parent_renderer:)
    super(parent_renderer: parent_renderer)

    @state[:status] = "WhatsApp Web carregado dentro de WebContentView."
    @state[:url] = "https://web.whatsapp.com"
    @state[:sidebar_open] = true

    @webcontent = nil

    ui do
      script(src: "https://cdn.tailwindcss.com") +
        style(base_css) +
        div(class: "h-screen w-screen bg-[#f4f4f4] text-[#161616]") do
          div(class: "flex h-full") do
            render_sidebar +
              div(class: "relative flex-1") do
                render_topbar +
                  embedded_browser_element(
                  id: "whatsapp_web",
                  url: "https://web.whatsapp.com",
                  visible: true,
                  x: 320,
                  y: 64,
                  width: 1360,
                  height: 820,
                  host_content: "Carregando WhatsApp Web...",
                  class: "absolute left-0 right-0 bottom-0 top-[64px] border-l border-[#d0d0d0] bg-white"
                )
              end
          end
        end
    end
  end

  def mounted
    create_whatsapp_webcontent
  end

  def create_whatsapp_webcontent
    return if @webcontent

    # O $surface_parent é o Composite SWT que contém o browser principal.
    # O WebContentView é outro Browser SWT posicionado por cima/ao lado.
    #
    # Ajuste inicial:
    # - sidebar: 320 px
    # - topbar: 64 px
    # - largura shell: 1440
    # - altura shell: 900
    #
    @webcontent = WebContentView.new(
      parent: $surface_parent,
      url: @state[:url],
      x: 320,
      y: 64,
      width: 1120,
      height: 836
    )

    set_state(:status, "Abra o QR Code no WhatsApp do celular para autenticar.", replace: true)
    nil
  end

  def render_sidebar
    aside(class: "w-[320px] shrink-0 border-r border-[#d0d0d0] bg-white p-5") do
      div("Glauco Framework", class: "text-xs font-semibold uppercase tracking-[0.24em] text-[#525252]") +
        h1("WhatsApp Web", class: "mt-3 text-3xl font-semibold tracking-tight") +
        p(
          "Exemplo de página externa persistente dentro de um WebContentView nativo.",
          class: "mt-3 text-sm leading-6 text-[#525252]"
        ) +
        div(class: "mt-6 space-y-3") do
          button(
            "Abrir WhatsApp Web",
            class: button_class("primary"),
            onclick: proc { open_whatsapp }
          ) +
            button(
              "Recarregar",
              class: button_class("secondary"),
              onclick: proc { reload_webcontent }
            ) +
            button(
              "Voltar",
              class: button_class("secondary"),
              onclick: proc { webcontent_back }
            ) +
            button(
              "Avançar",
              class: button_class("secondary"),
              onclick: proc { webcontent_forward }
            )
        end +
        div(class: "mt-8 border-t border-[#e0e0e0] pt-5") do
		label(
			"Buscar conversa",
			class: "mb-2 block text-xs font-semibold uppercase tracking-[0.18em] text-[#525252]"
		) +
			textarea(
				@state[:contact_query].to_s,
				rows: "2",
				placeholder: "Digite o nome da conversa",
				class: "w-full resize-none border border-[#8d8d8d] bg-[#f4f4f4] p-3 text-sm leading-6 outline-none focus:border-[#0f62fe]",
				oninput: proc { |value|
					set_state(:contact_query, value.to_s, replace: true)
				}
				) +
				button(
				"Buscar no WhatsApp",
				class: button_class("primary mt-3"),
				onclick: proc {


					query = @state[:contact_query].to_s.strip

					if query.empty?
					set_state(:status, "Digite o nome da conversa.", replace: true)
					next nil
					end

					capture_js = <<~JS
					const list = document.querySelector('[aria-label="Lista de conversas"]');

					if (!list) {
						return JSON.stringify({
						ok: false,
						error: 'Lista de conversas não encontrada.'
						});
					}

					const cells = Array.from(
						list.querySelectorAll('[data-testid="cell-frame-container"]')
					).map((cell, index) => {
						const titles = Array.from(
						cell.querySelectorAll('span[title]')
						).map(span => span.getAttribute('title') || '').filter(Boolean);

						return {
						index,
						text: cell.innerText || '',
						titles
						};
					});

					return JSON.stringify({
						ok: true,
						cells
					});
					JS

					Frontend.async_evaluate_embedded_browser_js("whatsapp_web", capture_js) do |payload|
					begin
						data = JSON.parse(payload.to_s)

						unless data["ok"]
						set_state(:status, data["error"].to_s, replace: true)
						next
						end

						api_key = ENV["GEMINI_API_KEY"].to_s.strip
						raise "GEMINI_API_KEY ausente" if api_key.empty?

						prompt = <<~PROMPT
						Você receberá uma lista de conversas extraída do WhatsApp Web.

						Cada conversa veio de um elemento:
						[data-testid="cell-frame-container"]

						Cada item contém possíveis nomes extraídos de:
						span[title]

						Texto buscado pelo usuário:
						#{query}

						Lista de conversas:
						#{JSON.pretty_generate(data["cells"])}

						Retorne apenas JSON válido neste formato:

						{
							"found": true,
							"title": "texto exato do span title encontrado"
						}

						Se não encontrar:

						{
							"found": false,
							"title": null
						}
						PROMPT

						uri = URI(
						"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent"
						)

						req = Net::HTTP::Post.new(uri)
						req["Content-Type"] = "application/json"
						req["x-goog-api-key"] = api_key

						req.body = JSON.generate(
						contents: [
							{
							parts: [
								{ text: prompt }
							]
							}
						],
						generationConfig: {
							responseMimeType: "application/json"
						}
						)

						res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
						http.request(req)
						end

						raise "Gemini HTTP #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

						gemini_data = JSON.parse(res.body)
						gemini_text = gemini_data.dig("candidates", 0, "content", "parts", 0, "text").to_s
						result = JSON.parse(gemini_text)

						unless result["found"] && result["title"]
						set_state(:status, "Conversa não encontrada pelo Gemini.", replace: true)
						next
						end

						title = result["title"].to_s

						click_js = <<~JS
							const targetTitle = #{JSON.generate(title)};

							const list = document.querySelector('[aria-label="Lista de conversas"]');

							if (!list) {
								return JSON.stringify({
								ok: false,
								error: 'Lista de conversas não encontrada.'
								});
							}

							const cells = Array.from(
								list.querySelectorAll('[data-testid="cell-frame-container"]')
							);

							const found = cells.find(cell => {
								return Array.from(cell.querySelectorAll('span[title]')).some(span => {
								return (span.getAttribute('title') || '').trim() === targetTitle.trim();
								});
							});

							if (!found) {
								return JSON.stringify({
								ok: false,
								error: 'Título retornado pelo Gemini não foi localizado no DOM atual.',
								title: targetTitle
								});
							}

							found.scrollIntoView({ block: 'center', inline: 'nearest' });

							const rect = found.getBoundingClientRect();

							const centerX = rect.left + rect.width / 2;
							const centerY = rect.top + rect.height / 2;

							found.click();

							return JSON.stringify({
								ok: true,
								clickedTitle: targetTitle,
								center: {
								x: centerX,
								y: centerY
								},
								rect: {
								left: rect.left,
								top: rect.top,
								right: rect.right,
								bottom: rect.bottom,
								width: rect.width,
								height: rect.height
								},
								viewport: {
								width: window.innerWidth,
								height: window.innerHeight,
								scrollX: window.scrollX,
								scrollY: window.scrollY
								}
							});
							JS

						Frontend.async_evaluate_embedded_browser_js("whatsapp_web", click_js) do |click_result|
						begin
							click_data = JSON.parse(click_result.to_s)

							unless click_data["ok"]
							set_state(:status, JSON.pretty_generate(click_data), replace: true)
							next
							end

							center = click_data["center"]
							embedded_x = center["x"].to_f
							embedded_y = center["y"].to_f

							surface = Frontend.embedded_browser_surface("whatsapp_web")
							raise "Embedded browser whatsapp_web não encontrado" unless surface

							screen_point = surface.toDisplay(embedded_x.round, embedded_y.round)

							robot = Robot.new
							robot.mouseMove(screen_point.x, screen_point.y)
							robot.delay(80)
							robot.mouseMove(screen_point.x + 1, screen_point.y)
							robot.delay(80)
							robot.mousePress(InputEvent::BUTTON1_DOWN_MASK)
							robot.delay(60)
							robot.mouseRelease(InputEvent::BUTTON1_DOWN_MASK)

							set_state(
							:status,
							[
								"Resultado Gemini:",
								JSON.pretty_generate(result),
								"",
								"Mouse movido para:",
								JSON.pretty_generate({
								embedded: {
									x: embedded_x,
									y: embedded_y
								},
								screen: {
									x: screen_point.x,
									y: screen_point.y
								},
								clickedTitle: click_data["clickedTitle"]
								})
							].join("\n"),
							replace: true
							)
						rescue => e
							set_state(
							:status,
							"#{e.class}: #{e.message}",
							replace: true
							)
						end
						end
					rescue => e
						set_state(:status, "#{e.class}: #{e.message}", replace: true)
					end
					end

					nil
				}
			)
		end
    end
  end

  def render_topbar
    header(class: "absolute left-0 right-0 top-0 flex h-[64px] items-center justify-between border-b border-[#d0d0d0] bg-white px-5") do
      div do
        div("WebContentView", class: "text-xs font-semibold uppercase tracking-[0.2em] text-[#525252]") +
          bind(:status, p(class: "mt-1 text-sm text-[#262626]")) do |status|
            status.to_s
          end
      end +
        div(class: "text-xs text-[#525252]") do
          "Perfil persistente: ~/.glauco/profiles/whatsapp-web-main/webview2"
        end
    end
  end

  def open_whatsapp
    ensure_webcontent
    @webcontent.navigate("https://web.whatsapp.com")
    set_state(:url, "https://web.whatsapp.com", replace: true)
    set_state(:status, "WhatsApp Web aberto.", replace: true)
    nil
  end

  def navigate_current_url
    ensure_webcontent

    url = @state[:url].to_s.strip
    url = "https://#{url}" unless url.start_with?("http://", "https://")

    @webcontent.navigate(url)
    set_state(:url, url, replace: true)
    set_state(:status, "Navegando para #{url}", replace: true)
    nil
  end

  def reload_webcontent
    ensure_webcontent
    @webcontent.reload
    set_state(:status, "WebContentView recarregado.", replace: true)
    nil
  end

  def webcontent_back
    ensure_webcontent
    @webcontent.back
    set_state(:status, "Comando voltar enviado.", replace: true)
    nil
  end

  def webcontent_forward
    ensure_webcontent
    @webcontent.forward
    set_state(:status, "Comando avançar enviado.", replace: true)
    nil
  end

  def ensure_webcontent
    create_whatsapp_webcontent unless @webcontent
  end

  def button_class(kind)
    base = "block w-full border px-4 py-3 text-left text-sm font-semibold transition"
    case kind
    when /primary/
      "#{base} border-[#0f62fe] bg-[#0f62fe] text-white hover:bg-[#0043ce] #{kind.to_s.sub("primary", "")}"
    else
      "#{base} border-[#8d8d8d] bg-white text-[#161616] hover:bg-[#e8e8e8] #{kind.to_s.sub("secondary", "")}"
    end
  end

  def base_css
    <<~CSS
      body {
        margin: 0;
        overflow: hidden;
        font-family: "Segoe UI", Arial, sans-serif;
        background: #f4f4f4;
      }

      textarea:focus {
        box-shadow: inset 0 0 0 1px #0f62fe;
      }
    CSS
  end
end

# ------------------------------------------------------------
# Renderização
# ------------------------------------------------------------

app = WhatsAppWebStudio.new(parent_renderer: $root)

$root.root_component = app
$root.render

$display.async_exec do
  Frontend.show_embedded_browser("whatsapp_web")
end

Frontend.start!