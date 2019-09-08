use `isucari`;

CREATE INDEX created_at_id_category_idx ON items (created_at, id, category_id);
CREATE INDEX buyer_id_created_at_idx ON items (buyer_id, created_at);
CREATE INDEX seller_id_created_at_idx ON items (seller_id, created_at);