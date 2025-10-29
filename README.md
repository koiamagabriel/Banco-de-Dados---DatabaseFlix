# SVOD — Plataforma de streaming (Projeto Multi-banco de Dados)

> **Tema**: Uma plataforma simples de streaming (sem cobrança real) com **catálogo** de filmes/séries, **login/cadastro**, filtros por **gêneros** e **atores**, e marcação de **“curtidos”** (likes).  
> **Objetivo acadêmico**: estudar **armazenamento** e **consulta** em múltiplos bancos, escolhendo o tipo de banco **pelo uso do dado**.

---

## ✅ Tema escolhido (explicação)

Escolhemos streaming porque divide naturalmente o problema em partes com necessidades diferentes:

- **Cadastro/Autenticação** de usuários e **logs** de requisições → exigem **integridade, unicidade e transações** ⇒ **Relacional**.  
- **Catálogo** (filmes/séries) com campos variáveis (sinopse, elenco, gêneros, temporadas/episódios/duração) → pede **flexibilidade de schema** e **busca por texto** ⇒ **Documento/NoSQL**.  
- **Relações** “**GOSTOU**”, “**PERTENCE_A**”, “**ATUOU_EM**” e interseção de filtros (Curtidos ∩ Gênero ∩ Ator) → modelagem **em grafo** é mais expressiva e eficiente ⇒ **Grafo**.

---

## 🧱 Arquitetura (S1/S2 e bancos)

```mermaid


graph LR
  UI[S1 - UI (Streamlit)] <--> API[S2 - FastAPI]
  API <--> RDB[(Supabase/Postgres)]
  API <--> DOC[(MongoDB - Catálogo)]
  API <--> GRAFO[(Neo4j - Relações)]
S1 (Streamlit): interface “tipo site” em Python (sem HTML/CSS), com telas de Login, Cadastro, Catálogo, Detalhe e Admin.

S2 (FastAPI): serviço HTTP que recebe as requisições do S1 e orquestra os bancos.

📚 Justificativa de cada banco & como o S2 usa
1) Supabase / PostgreSQL (Relacional)

Por quê: integridade, unicidade de e-mail, transações; ideal para autenticação e logs.

Armazena:

usuarios(id, nome, email UNIQUE, senha_hash, is_admin)

logs_s1(id, endpoint, metodo, req_payload, res_payload, status_code, latency_ms, erro, user_id, ts)

No S2: POST /usuarios, POST /auth/login e logging de todas as chamadas do S1.

2) MongoDB (Documento / Catálogo)

Por quê: schema flexível (filme ≠ série), índice de texto para busca.

Coleção titulos:

Comum: titulo, tipo (filme|serie), sinopse, classificacao, generos[], elenco[], ano, disponivel

Filme: duracao_min

Série: temporadas, eps_por_temp[]

No S2: depois de obter IDs de títulos via Neo4j, busca os documentos no Mongo (compatível com _id ObjectId ou string) e aplica q (texto).

3) Neo4j (Grafo)

Por quê: consultas por relacionamento/navegação e interseção de filtros.

Nós/arestas:

Nós: (:User {id}), (:Title {id,titulo,tipo}), (:Genre {nome}), (:Actor {nome})

Arestas: (:User)-[:GOSTOU]->(:Title), (:Title)-[:PERTENCE_A]->(:Genre), (:Actor)-[:ATUOU_EM]->(:Title)

No S2: Neo4j-first para filtros (generos, ator, curtidos):

Consulta o grafo e calcula IDs (fazendo interseção quando há mais de um filtro).

Com esses IDs, busca os docs no Mongo e retorna ao S1.

⚙️ Implementação do S2 (FastAPI)

Rotas principais:

POST /usuarios → cria usuário no Supabase (senha com bcrypt).

POST /auth/login → valida senha.

GET /catalogo → rota unificada: aceita q, generos, ator, curtidos, user_id, limite, pular.

Se houver generos/ator/curtidos → Neo4j → IDs → Mongo.

Se não houver filtros de grafo → consulta direta no Mongo (com q, generos, ator).

GET /catalogo/{id} → detalhe (Mongo).

GET /catalogo/generos → lista gêneros (Mongo).

POST /grafo/gostou / DELETE /grafo/gostou → toggle de curtida (Neo4j).

Admin:

POST /admin/titulos → insere título (Mongo) e sincroniza nós/arestas no grafo.

GET /admin/titulos/lista → lista para exclusão.

DELETE /admin/titulos/{id} → exclui no Mongo e DETACH DELETE no Neo4j.

Resiliência:

Compat quando disponivel não existe (legado).

Busca por _id funciona com ObjectId ou string (pipeline com $toString).

startup cria constraints/índices e semente mínima.

🖥️ Execução do projeto
0) Pré-requisitos

Python 3.11+

Instâncias e credenciais:

Supabase (Postgres) → SUPABASE_URL, SUPABASE_KEY

MongoDB Atlas → MONGODB_URI, MONGODB_DBNAME

Neo4j (AuraDB/servidor) → NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD

⚠️ Segurança: as credenciais são lidas de db/*.py. Não publique segredos reais.

1) Estrutura de pastas
Projeto/
├─ s1/
│  └─ app.py
├─ s2/
│  └─ main.py
├─ db/
│  ├─ supabase_rest.py
│  ├─ mongo.py
│  └─ neo4j_db.py
└─ sanity_check.py

2) Instalar dependências
py -m pip install --upgrade pip
py -m pip install fastapi "uvicorn[standard]" pydantic[email] requests streamlit pymongo neo4j bcrypt certifi


Se der problema com bcrypt no Windows:

py -m pip install passlib[bcrypt]

3) Configurar conexões

db/supabase_rest.py → SUPABASE_URL, SUPABASE_KEY

db/mongo.py → MONGODB_URI, MONGODB_DBNAME

db/neo4j_db.py → NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD

Dica: se for certificado self-signed, use neo4j+ssc://.

4) Subir o S2 (API)
py -m uvicorn s2.main:app --reload --port 8000


Teste:

GET http://127.0.0.1:8000/health
# → { "ok": true, "neo4j": true/false }

5) Subir o S1 (UI)
py -m streamlit run s1/app.py


Abra o link indicado (geralmente http://localhost:8501).

6) Primeiro uso

Cadastre-se.

Torne o usuário admin (no Supabase usuarios.is_admin=true ou via POST /usuarios com is_admin:true).

Entre como admin → Admin → cadastre títulos (filme/série).

No Catálogo: busque por q, filtre por Gêneros/Ator, clique Gostei ❤️ e use o filtro Curtidos.

🧭 Funcionalidades

Login/Cadastro (Supabase/Postgres).

Catálogo (Mongo): busca por texto, filtros por Gêneros (checkbox), Ator (chips) e Curtidos.

Detalhe: botões de filtro por ator/gênero e Gostei/Descurtir.

Admin: cadastrar/excluir títulos (sincroniza grafos).

Filtros Neo4j-first: interseção natural Curtidos ∩ Gêneros ∩ Ator.
