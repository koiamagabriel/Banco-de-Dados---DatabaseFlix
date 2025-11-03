# DatabaseFlix — Plataforma de streaming 

## Tema escolhido 

  Escolhemos uma plataforma de streaming porque ela reflete um cenário em que diferentes partes do sistema têm multiplas necessidades. O cadastro e a autenticação de usuários exigem uma das maiores funcionalidades de um banco de dados; O catálogo de títulos precisa de flexibilidade de multiplas informações para funcionar, além de integrar completamente com os bancos com sua funcionalidade de realizar buscas de obras; A experiência do usuário utiliza relacionamentos claros entre pessoas, obras, gêneros e atores, esse conjunto de requisitos nos permite aplicar, três tipos de bancos de dados – relacional, documentos e grafo – e mostrar na prática como a escolha do banco é guiada pelo tipo de dado e pelo padrão de consulta que a aplicação realiza.

---

## Arquitetura (S1/S2 e bancos)

- UI[S1 - UI (Streamlit)] <--> API[S2 - FastAPI]  
- API <--> RDB[(Supabase/Postgres)]  
- API <--> DOC[(MongoDB - Catálogo)]  
- API <--> GRAFO[(Neo4j - Relações)]

- **S1 (Streamlit)**: interface baseada em um site utilizando Python, com telas de Login, Cadastro, Planos de assinatura, Pagamento, Catálogo, Detalhe e Admin.  
- **S2 (FastAPI)**: serviço HTTP que recebe as informações do S1 e comanda os bancos.

---

## Justificativa de cada banco e como o S2 usa

**1. Supabase (Relacional)**

- **Por quê**: integridade, unicidade de e-mail; ideal para autenticação, **assinaturas**, **pagamentos (simulados)** e **logs**.
- **Armazena**:
  - `usuarios(id, nome, email UNIQUE, senha_hash, is_admin)`
  - `planos(codigo PRIMARY KEY, nome, descricao)`  ← **planos mensais**
  - `assinaturas(user_id UNIQUE, plano_codigo, status, created_at)`  ← **vínculo usuário-plano**
  - `pagamentos(id, user_id, plano_codigo, nome_impresso, last4, validade_mm, validade_aa, pais, endereco1, endereco2, cidade, estado, cep, ts)`  ← **pagamento simulado**
  - `log_s1(id, endpoint, metodo, req_payload, res_payload, status_code, latency_ms, erro, user_id, ts)`  ← **logs de chamadas do S1**
- **No S2**:
  - `POST /usuarios` e `POST /auth/login`
  - `GET /planos`, `POST /assinaturas`, `GET /assinaturas/me`, `POST /pagamentos`
  - S1 registra **todas as chamadas** (sucesso/erro) em `log_s1`.

**2. MongoDB (Documento / Catálogo)**

- **Por quê**: schema flexível (filme ≠ série) e índice de texto para busca.
- **Coleção `titulos`**:
  - Comum: `titulo`, `tipo` (`filme`|`serie`), `sinopse`, `classificacao`, `generos[]`, `elenco[]`, `ano`, `disponivel`
  - Filme: `duracao_min`
  - Série: `temporadas`, `eps_por_temp[]`
  - **Visibilidade por plano**: `vis_comum`, `vis_premium` 

**3. Neo4j (Grafo)**

- **Por quê**: consultas por relacionamento e interseção de filtros.
- **Nós/Arestas**:
  - Nós: `(:User {id})`, `(:Title {id,titulo,tipo})`, `(:Genre {nome})`, `(:Actor {nome})`
  - Arestas: `(:User)-[:GOSTOU]->(:Title)`, `(:Title)-[:PERTENCE_A]->(:Genre)`, `(:Actor)-[:ATUOU_EM]->(:Title)`
- **No S2 (estratégia Neo4j-first)**: quando há filtros por `generos`, `ator` e/ou `curtidos`, o S2 consulta o grafo para obter o conjunto de IDs (faz interseção quando mais de um filtro está ativo) e, com esses IDs, busca os documentos no Mongo.

---



## Definição de como o S2 será implementado

- **Framework**: FastAPI (Python).
- **Rotas principais**:
  - **Usuários**
    - `POST /usuarios` → cria usuário no Supabase (`senha_hash` com bcrypt).  
      **Regra de admin**: e-mails que **terminam com `@admin.com`** são marcados como `is_admin=true`.
    - `POST /auth/login` → valida credenciais no Supabase.
  - **Planos & Assinaturas**  
    - `GET /planos` → lista os planos cadastrados no Supabase (fallback na UI se vazio).
    - `GET /assinaturas/me?user_id=...` → retorna o plano atual do usuário, se existir.
    - `POST /assinaturas` → cria/atualiza assinatura `{ user_id, plano_codigo }`.
  - **Pagamento simulado**
    - `POST /pagamentos` → armazena **somente `last4`** do cartão + endereço .
  - **Catálogo**
    - `GET /catalogo`: parâmetros `q`, `generos`, `ator`, `curtidos`, `user_id`, `limite`, `pular`.
      - Com filtros de grafo → Neo4j → IDs → Mongo.
      - Sem filtros de grafo → Mongo direto (com restrição por plano).
    - `GET /catalogo/{id}` → detalhe (Mongo, com bloqueio por plano).
    - `GET /catalogo/generos` → lista de gêneros (Mongo).
  - **Grafo**
    - `POST /grafo/gostou` / `DELETE /grafo/gostou` → toggle de curtida.
    - `GET /grafo/curtidos?user_id=...&title_ids=CSV?` → ids curtidos (subset opcional).
  - **Admin**
    - `POST /admin/titulos` → insere no Mongo e sincroniza no grafo (gêneros/atores).
    - `GET /admin/titulos/lista` → lista para exclusão.
    - `DELETE /admin/titulos/{id}` → apaga do Mongo e `DETACH DELETE` no Neo4j.

---

## Como executar o projeto:

### Instalar os arquivos
- Baixe o Arquivo zipado do projeto.
- Configure seus bancos de dados para se adequar ao nosso.
- Crie as tabelas do supabase a partir do codigo anexado no projeto.

### Pré-requisitos

- Python 3.11 ou superior.
- Serviços/credenciais ativas:
  - Supabase (PostgreSQL) → `SUPABASE_URL`, `SUPABASE_KEY`, `SUPABASE_SERVICE_KEY`
  - MongoDB Atlas → `MONGODB_URI`, `MONGODB_DBNAME`
  - Neo4j (AuraDB ou servidor) → `NEO4J_URI`, `NEO4J_USER`, `NEO4J_PASSWORD`

### Instalar dependências

No PowerShell (Windows):
- py -m pip install --upgrade pip
- py -m pip install fastapi "uvicorn[standard]" pydantic[email] requests streamlit pymongo neo4j bcrypt certifi

### Configurar conexões

Edite os arquivos:

- `db/supabase_rest.py` → `SUPABASE_URL`, `SUPABASE_KEY`, `SUPABASE_SERVICE_KEY`
- `db/mongo.py` → `MONGODB_URI`, `MONGODB_DBNAME`
- `db/neo4j_db.py` → `NEO4J_URI`, `NEO4J_USER`, `NEO4J_PASSWORD`

### Subir o S2 (API)
- Abra um terminal:
  - py -m uvicorn s2.main:app --reload --port 8000

### Subir o S1 (UI)
- Em outro terminal:
  - py -m streamlit run s1/app.py
  - Abra o link mostrado.

### Primeiro uso


1. Cadastre-se na tela de cadastro.  
2. **Para ter acesso Admin**, cadastre usando e-mail que **termine em `@admin.com`**.  
3. Escolha um **plano** e faça o **pagamento** simulado
4. No Catálogo, utilize busca/filtros conforme seu plano e marque **Gostei/Descurtir** (Plano DELUX).  
5. Na tela **Admin**, cadastre títulos e  a exclua-os conforme necessário.

### Serviços que devem ser usados

- **Supabase (PostgreSQL)**: autenticação, **planos**, **assinaturas**, **pagamentos simulados** e **logs** das chamadas do S1.  
- **MongoDB Atlas**: catálogo de títulos (documentos flexíveis, índice de texto).  
- **Neo4j**: relacionamentos entre usuários, títulos, gêneros e atores, e controle de curtidas.


Esses três serviços devem estar acessíveis e corretamente configurados para a aplicação funcionar como esperado.


