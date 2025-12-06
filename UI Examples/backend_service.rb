# backend_service.rb
module BackendService
  def self.buscar_usuario(id)
    # Algo que poderia vir de banco, API, etc.
    sleep 0.5
    {
      id: id,
      nome: "Usuário #{id}",
      premium: id.to_i.even?
    }
  end
end
