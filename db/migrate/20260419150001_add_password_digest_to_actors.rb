class AddPasswordDigestToActors < ActiveRecord::Migration[8.1]
  def change
    add_column :actors, :password_digest, :string
  end
end
