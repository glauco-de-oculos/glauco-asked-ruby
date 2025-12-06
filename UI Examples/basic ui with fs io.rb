require_relative '../glauco-framework'
include Frontend

class Contador < Component
  def initialize(parent_renderer:)
    super(parent_renderer: parent_renderer)

    @state[:valor] = 0
    @state[:status] = ""

    ui do
      div(style: "padding:20px; font-family:sans-serif") do
        
        # Valor atual
        bind(:valor, h1) do |v| "Valor: #{v}" end +

        # Botões básicos
        div(style: "margin-top:20px; display:flex; gap:10px") do
          button(style:"padding:10px", onclick: proc {
            set_state(:valor, @state[:valor] + 1)
          }) { "+" } +

          button(style:"padding:10px", onclick: proc {
            set_state(:valor, @state[:valor] - 1)
          }) { "-" } +

          button(style:"padding:10px", onclick: proc {
            set_state(:valor, 0)
          }) { "Reset" }
        end +

        # Botões de File IO
        div(style:"margin-top:30px; display:flex; gap:10px") do
          
          # SALVAR
          button(style:"padding:10px", onclick: proc {
            begin
              File.write("valor.txt", @state[:valor].to_s)
              set_state(:status, "Valor salvo em valor.txt")
            rescue => e
              set_state(:status, "Erro ao salvar: #{e.message}")
            end
          }) { "Salvar em arquivo" } +

          # CARREGAR
          button(style:"padding:10px", onclick: proc {
            begin
              if File.exist?("valor.txt")
                val = File.read("valor.txt").to_i
                set_state(:valor, val)
                set_state(:status, "Valor carregado do arquivo")
              else
                set_state(:status, "Arquivo valor.txt não encontrado")
              end
            rescue => e
              set_state(:status, "Erro ao carregar: #{e.message}")
            end
          }) { "Carregar arquivo" }
        end +

        # Área de status
        bind(:status, p) do |msg| msg end
      end
    end
  end
end

app = Contador.new(parent_renderer: $root)
$root.root_component = app
$root.render

$shell.setSize(600, 400)
$shell.open
