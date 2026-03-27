# =========================================
# 📦 REQUIRE
# =========================================
require_relative '../core/framework/glauco-framework'
include Frontend

java_import 'org.eclipse.swt.widgets.DirectoryDialog'

# =========================================
# 🖼️ APP
# =========================================
class ImageViewerApp < Frontend::Component
  	def initialize(parent_renderer:)
		super(parent_renderer: parent_renderer)

		@state[:images] = []
		@state[:selected] = nil
		@state[:base_path] = nil

		# =========================================
		# 🎨 UI
		# =========================================
		ui do
			ui_shell do
				# =========================
				# GRID LAYOUT ROOT
				# =========================
				div(
					style: "
						display: grid;
						grid-template-columns: 280px 1fr;
						grid-template-rows: auto 1fr;
						height: 100vh;
					"
				) do
					# =========================
					# HEADER
					# =========================
					header(
						style: "
							grid-column: 1 / span 2;
							grid-row: 1;
							z-index: 10;
						"
					) do
						header_name { "Image Viewer" } +

						button(
							onclick: proc {
								async { select_folder }
							},
							kind: "primary"
						) { "Selecionar pasta" }
					end +

					# =========================
					# SIDEBAR
					# =========================
					side_nav(
						expanded: true,
						style: "
							grid-column: 1;
							grid-row: 2;
							position: relative !important;
							height: 100%;
						"
					) do
						side_nav_items() do
							bind(:images, div) do |images|
								images.map do |img|
									side_nav_link(
										onclick: proc {
											set_state(:selected, img)
										}
									) { File.basename(img) }
								end
							end
						end
					end +

					# =========================
					# CONTENT
					# =========================
					content(
						style: "
							grid-column: 2;
							grid-row: 2;
							overflow: auto;
						"
					) do
						div(
							style: "
								width: 100%;
								max-width: 1200px;
								height: 100%;
								display: flex;
								flex-direction: column;
								align-items: center;
								justify-content: center;
								background: var(--cds-layer);
								border-radius: 12px;
								padding: 1.5rem;
								box-shadow: 0 8px 24px rgba(0,0,0,0.2);
							"
						) do
							bind(
								:selected,
								div(style: 'width:100%; height:100%; display:flex; align-items:center; justify-content:center;')
							) do |selected|
								if selected
									img(
										src: "#{Frontend.base_url}/files/#{selected.gsub("\\", "/")}",
										style: "
											max-width: 100%;
											max-height: 100%;
											object-fit: contain;
											border-radius: 8px;
										"
									)
								else
									div(style: "color: #aaa; font-size: 1.2rem;") do
										"Selecione uma imagem"
									end
								
								end
							end
						end
					end
				end
			end
		end
	end

	# =========================================
	# 📂 Selecionar pasta (SWT)
	# =========================================
	def select_folder
		dialog = DirectoryDialog.new($shell)
		dialog.setText("Selecionar pasta de imagens")

		path = dialog.open
		return unless path

		images = Dir.glob(File.join(path, "*.{png,jpg,jpeg,gif}"))

		set_state(:images, images)
		set_state(:base_path, path)
	end
end

$app = ImageViewerApp.new(parent_renderer: $root)
$root.root_component = $app
$root.render

$shell.setSize(1200, 800)

Frontend::start!
