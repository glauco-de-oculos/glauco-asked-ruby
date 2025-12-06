require_relative '../glauco-framework'
include Frontend

class CartaoAnimado < Component
  def initialize(parent_renderer:)
    super(parent_renderer: parent_renderer)

    @state[:msg] = "Passe o mouse…"

    define_render do
      # HTML puro com CSS e animação
      html = <<~HTML
        <style>
          .card {
            width: 300px;
            padding: 20px;
            margin: 40px;
            border-radius: 15px;
            background: linear-gradient(135deg, #2b2bff, #8f00ff);
            color: white;
            font-family: Arial, sans-serif;
            box-shadow: 0 8px 20px rgba(0,0,0,0.3);
            transition: transform .3s ease, box-shadow .3s ease;
            cursor: pointer;
          }

          .card:hover {
            transform: scale(1.07) rotate(1deg);
            box-shadow: 0 12px 30px rgba(0,0,0,0.4);
          }

          .msg {
            font-size: 24px;
            font-weight: bold;
            margin-bottom: 15px;
            opacity: 0;
            animation: fadeIn .6s forwards ease-out;
          }

          @keyframes fadeIn {
            from { opacity: 0; transform: translateY(10px); }
            to   { opacity: 1; transform: translateY(0); }
          }

          .botao {
            padding: 10px 15px;
            background: rgba(255,255,255,0.2);
            border: 1px solid rgba(255,255,255,0.4);
            border-radius: 8px;
            color: white;
            backdrop-filter: blur(3px);
            transition: background .25s, transform .25s;
          }

          .botao:hover {
            background: rgba(255,255,255,0.35);
            transform: scale(1.05);
          }
        </style>
      HTML

      # Bloco com bind + HTML direto
      html +
        "<div class='card'>" +

        bind(:msg, "<div class='msg'>") { |m| m.to_s } +

        button(class:"botao", onclick: proc {
          set_state(:msg, "Boom! CSS + HTML puro + Ruby.")
        }) { "Mudar texto" } +

        "</div>"
    end
  end
end


app = CartaoAnimado.new(parent_renderer: $root)
$root.root_component = app
$root.render

$shell.setSize(600, 500)
$shell.open
