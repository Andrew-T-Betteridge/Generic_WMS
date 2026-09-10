INSERT INTO core.client (client_id, description)
VALUES ('FINATICS', 'FINatics Aquatics')
ON CONFLICT (client_id) DO NOTHING;
