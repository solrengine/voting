class DropTokens < ActiveRecord::Migration[8.1]
  def change
    drop_table :tokens do |t|
      t.datetime :created_at, null: false
      t.integer :decimals
      t.string :icon
      t.string :mint, null: false
      t.string :name
      t.string :symbol
      t.string :token_program
      t.datetime :updated_at, null: false
      t.boolean :verified, default: false
      t.index [ :mint ], name: "index_tokens_on_mint", unique: true
    end
  end
end
