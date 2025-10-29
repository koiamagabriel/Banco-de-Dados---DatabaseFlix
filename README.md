# DatabaseFlix — Plataforma de streaming (Projeto Multi-banco de Dados)

---

## Tema escolhido (explicação)

Escolhemos uma plataforma de streaming porque ela reflete um cenário real em que diferentes partes do sistema têm necessidades distintas e complementares. O cadastro e a autenticação de usuários exigem integridade, unicidade de e-mail e transações confiáveis; o catálogo de títulos precisa de flexibilidade de schema para lidar com filmes e séries (com campos diferentes, como duração ou temporadas/episódios) e também de busca por texto; e a experiência do usuário demanda relacionamentos claros entre pessoas, obras, gêneros e atores, além de funcionalidades sociais como curtidas. Esse conjunto de requisitos nos permite aplicar, de forma coerente, três tecnologias de bancos de dados – relacional, documentos e grafo – e mostrar na prática como a escolha do banco é guiada pelo tipo de dado e pelo padrão de consulta que a aplicação realiza.

---

## Arquitetura (S1/S2 e bancos)

graph LR  
- UI[S1 - UI (Streamlit)] <--> API[S2 - FastAPI]  
- API <--> RDB[(Supabase/Postgres)]  
- API <--> DOC[(MongoDB - Catálogo)]  
- API <--> GRAFO[(Neo4j - Relações)]

- S1 (Streamlit): interface “tipo site” em Python (sem HTML/CSS), com telas de Login, Cadastro, Catálogo, Detalhe e Admin.  
- S2 (FastAPI): serviço HTTP que recebe as requisições do S1 e orquestra os bancos.

---

## Justificativa de cada banco e como o S2 usa

**1. Supabase / PostgreSQL (Relacional)**

- Por quê: integridade, unicidade de e-mail, transações; ideal para autenticação e logs.
- Armazena:
  - `usuarios(id, nome, email UNIQUE, senha_hash, is_admin)`
  - `logs_s1(id, endpoint, metodo, req_payload, res_payload, status_code, latency_ms, erro, user_id, ts)`
- No S2: `POST /usuarios`, `POST /auth/login` e logging de todas as chamadas do S1.

**2. MongoDB (Documento / Catálogo)**

- Por quê: schema flexível (filme ≠ série) e índice de texto para busca.
- Coleção `titulos`:
  - Comum: `titulo`, `tipo` (`filme`|`serie`), `sinopse`, `classificacao`, `generos[]`, `elenco[]`, `ano`, `disponivel`
  - Filme: `duracao_min`
  - Série: `temporadas`, `eps_por_temp[]`
- No S2: depois de obter IDs de títulos pelo Neo4j, busca os documentos no Mongo (compatível com `_id` ObjectId ou string) e aplica a busca textual `q`.

**3. Neo4j (Grafo)**

- Por quê: consultas por relacionamento e interseção de filtros.
- Nós/arestas:
  - Nós: `(:User {id})`, `(:Title {id,titulo,tipo})`, `(:Genre {nome})`, `(:Actor {nome})`
  - Arestas: `(:User)-[:GOSTOU]->(:Title)`, `(:Title)-[:PERTENCE_A]->(:Genre)`, `(:Actor)-[:ATUOU_EM]->(:Title)`
- No S2 (estratégia Neo4j-first): quando há filtros por `generos`, `ator` e/ou `curtidos`, o S2 consulta o grafo para obter o conjunto de IDs (fazendo interseção quando mais de um filtro está ativo) e, com esses IDs, busca os documentos no Mongo.

---

## Definição de como o S2 será implementado

- **Framework**: FastAPI (Python).
- **Rotas principais**:
  - `POST /usuarios` → cria usuário no Supabase (com `senha_hash` usando bcrypt).
  - `POST /auth/login` → valida as credenciais no Supabase.
  - `GET /catalogo` → rota unificada do catálogo:
    - Parâmetros: `q`, `generos`, `ator`, `curtidos`, `user_id`, `limite`, `pular`.
    - Se houver `generos`/`ator`/`curtidos`: S2 consulta o **Neo4j** para determinar os IDs de títulos e depois retorna os documentos a partir do **MongoDB**.
    - Se não houver filtros de grafo: consulta direta no **MongoDB** (com `q`, `generos`, `ator`).
  - `GET /catalogo/{id}` → detalhe do título (Mongo).
  - `GET /catalogo/generos` → lista de gêneros existentes (Mongo).
  - `POST /grafo/gostou` / `DELETE /grafo/gostou` → toggle de curtida (Neo4j).
  - Admin:
    - `POST /admin/titulos` → insere filme/série no Mongo e sincroniza nós/arestas no grafo.
    - `GET /admin/titulos/lista` → lista simplificada de títulos para exclusão.
    - `DELETE /admin/titulos/{id}` → exclui do Mongo e executa `DETACH DELETE` no Neo4j.

Observações de robustez:
- Compatibilidade quando o campo `disponivel` ainda não existir (legado).
- Pipeline no Mongo lida com `_id` do tipo `ObjectId` ou string (usando `$toString`).
- Processo de startup cria índices/constraints e sementes mínimas quando necessário.

---

## Como executar o projeto

### Pré-requisitos

- Python 3.11 ou superior.
- Serviços/credenciais ativas:
  - Supabase (PostgreSQL) → `SUPABASE_URL`, `SUPABASE_KEY`
  - MongoDB Atlas → `MONGODB_URI`, `MONGODB_DBNAME`
  - Neo4j (AuraDB ou servidor) → `NEO4J_URI`, `NEO4J_USER`, `NEO4J_PASSWORD`

As credenciais são lidas em `db/*.py`. Não publique segredos reais em repositórios públicos.

### Estrutura de pastas

