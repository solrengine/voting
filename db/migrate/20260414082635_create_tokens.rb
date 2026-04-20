class CreateTokens < ActiveRecord::Migration[7.1]
  def change
    create_table :tokens do |t|
      t.string :mint, null: false
      t.string :name
      t.string :symbol
      t.string :icon
      t.integer :decimals
      t.string :token_program
      t.boolean :verified, default: false

      t.timestamps
    end
    add_index :tokens, :mint, unique: true
  end
end
