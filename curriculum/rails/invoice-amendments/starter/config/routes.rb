Rails.application.routes.draw do
  patch "/invoices/:id", to: "invoices#update"
end
