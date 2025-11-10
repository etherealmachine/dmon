class CreatePdfs < ActiveRecord::Migration[8.0]
  def change
    create_table :pdfs do |t|
      t.string :name
      t.text :description
      t.text :text_content
      t.text :html_content
      t.references :game, null: false, foreign_key: true

      t.timestamps
    end
  end
end
