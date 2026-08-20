# Aplicativo Inteligente de Gestão Automotiva

## Documento-base para desenvolvimento — V1

---

# 1. Visão do produto

Criar um aplicativo mobile que funcione como um **assistente pessoal inteligente do veículo**.

O aplicativo acompanha:

* abastecimentos;
* consumo;
* quilometragem;
* gastos;
* manutenções;
* revisões;
* pneus;
* óleo;
* filtros;
* documentação;
* valor do veículo;
* histórico do veículo.

A IA utiliza esses dados para:

* responder perguntas;
* identificar alterações;
* explicar informações;
* gerar alertas;
* antecipar necessidades;
* auxiliar o usuário na manutenção do veículo.

## Conceito central

> **O usuário não deve precisar cuidar do aplicativo. O aplicativo deve ajudar o usuário a cuidar do carro.**

---

# 2. Posicionamento

Não posicionar inicialmente como:

> "Aplicativo para controlar combustível."

Posicionar como:

> **"Seu carro, agora inteligente."**

ou:

> **"Um assistente inteligente para cuidar do seu carro."**

O aplicativo deve ser percebido como um **painel inteligente do veículo**, e não como uma planilha de gastos.

---

# 3. Público inicial

Principalmente:

* proprietários de carros particulares;
* usuários de renda baixa e média;
* pessoas que abastecem frequentemente;
* pessoas que não entendem profundamente de mecânica;
* pessoas que esquecem revisões e manutenções;
* pessoas interessadas em economizar combustível;
* pessoas que querem entender quanto realmente gastam com o carro.

## Premissa importante

O usuário não precisa:

* completar o tanque;
* registrar todos os abastecimentos perfeitamente;
* entender de mecânica;
* saber calcular consumo;
* preencher dezenas de campos.

A experiência deve funcionar mesmo com dados incompletos.

---

# 4. MVP

O MVP deve conter apenas o necessário para provar que existe uso recorrente.

## Módulo 1 — Conta

* cadastro;
* login;
* recuperação de senha;
* logout.

Preferencialmente utilizar autenticação pronta do Supabase.

---

# 5. Módulo 2 — Cadastro do veículo

Campos iniciais:

* marca;
* modelo;
* versão;
* ano;
* motorização, quando disponível;
* combustível;
* quilometragem atual.

O usuário poderá ter inicialmente **1 veículo**.

Múltiplos veículos ficam para Premium/futuro.

## Objetivo

Ao cadastrar o veículo, o aplicativo deve começar a construir o histórico daquele carro.

---

# 6. Módulo 3 — Abastecimento

Registro:

* data;
* quilometragem;
* valor total;
* litros;
* preço por litro;
* combustível;
* tanque cheio: sim/não;
* posto/localização, quando disponível;
* observação opcional.

## Campos que podem ser calculados automaticamente

Se o usuário informar:

* valor;
* litros;

o sistema calcula:

> preço/litro = valor ÷ litros

Se informar:

* litros;
* preço/litro;

o sistema calcula:

> valor = litros × preço/litro

---

# 7. Detecção de posto

Uma das principais funcionalidades de automação.

Quando o usuário estiver próximo/entrar em um posto:

> ⛽ **Abasteceu?**

Botões:

**Registrar abastecimento**

**Agora não**

A detecção não deve obrigar o usuário a registrar.

## Objetivo

Reduzir o esquecimento.

O usuário não deve precisar lembrar:

> "Preciso abrir o aplicativo."

O aplicativo deve lembrá-lo.

---

# 8. Cálculo de consumo

## Regra principal

O aplicativo NÃO deve tentar adivinhar a quantidade de combustível existente no tanque.

O cálculo de alta precisão deve utilizar ciclos entre abastecimentos completos.

Exemplo:

### Abastecimento 1

50.000 km
40 L
Tanque cheio

### Abastecimento 2

50.400 km
20 L
Parcial

### Abastecimento 3

50.700 km
25 L
Parcial

### Abastecimento 4

51.000 km
35 L
Tanque cheio

Litros consumidos:

20 + 25 + 35 = 80 L

Distância:

1.000 km

Consumo:

12,5 km/L

---

# 9. Consumo estimado

O aplicativo deve continuar funcionando mesmo sem dois tanques cheios.

### Alta confiança

Dados suficientes entre abastecimentos completos.

Mostrar:

> 🟢 Consumo confirmado: 10,7 km/L

### Média confiança

Vários abastecimentos, mas sem fechamento completo.

Mostrar:

> 🟡 Consumo estimado: 10,3 km/L

### Baixa confiança

Poucos dados.

Mostrar:

> 🔴 Ainda temos poucos dados para estimar seu consumo.

## Regra importante

Nunca apresentar uma estimativa como se fosse um valor exato.

---

# 10. Tratamento de abastecimento esquecido

O usuário pode esquecer um abastecimento.

O sistema deve permitir corrigir o histórico.

Exemplo:

> "Esqueci de registrar um abastecimento."

O usuário informa:

* data aproximada;
* quilometragem;
* litros;
* valor, se souber.

O algoritmo recalcula os dados posteriores.

---

# 11. Dashboard principal

A home deve ser visual e simples.

## Estrutura conceitual

### 🚗 Meu veículo

**Toyota Corolla 2020**

87.420 km

---

### Consumo

**10,7 km/L**

🟢 Alta confiança

---

### Gastos este mês

**R$ 684**

---

### Próximas atenções

🔧 Revisão — 2.300 km

🛢️ Óleo — 1.200 km

---

### IA

> "Seu carro está indo bem. Percebi apenas uma pequena queda no consumo nas últimas semanas."

**[Conversar com IA]**

---

# 12. Módulo de manutenção

Permitir registrar:

* troca de óleo;
* filtro de óleo;
* filtro de ar;
* filtro de combustível;
* pneus;
* pastilhas;
* bateria;
* correias;
* revisão;
* outros.

Cada registro:

* item;
* data;
* quilometragem;
* valor;
* observação;
* estabelecimento opcional.

---

# 13. Alertas de manutenção

O sistema deve utilizar:

* quilometragem;
* data;
* veículo;
* histórico;
* intervalos conhecidos.

Exemplo:

> 🔧 **Revisão se aproximando**
>
> Seu veículo está aproximadamente 1.800 km da próxima revisão estimada.

## Importante

Alertas devem ser tratados como recomendações.

Não afirmar:

> "Você precisa trocar sua pastilha agora."

Preferir:

> "Pelo histórico e intervalo estimado, pode ser interessante verificar as pastilhas."

---

# 14. Base de conhecimento automotivo

O sistema deverá futuramente possuir dados estruturados por:

* marca;
* modelo;
* versão;
* ano;
* motorização;
* combustível.

Informações:

* revisões;
* intervalos;
* itens de manutenção;
* especificações;
* recomendações.

## Não colocar toda essa lógica diretamente no LLM.

Os dados importantes devem existir em banco estruturado.

A IA interpreta esses dados.

---

# 15. IA — arquitetura

A IA não deve ser responsável por cálculos básicos.

## Backend calcula

Exemplos:

* km/L;
* custo/km;
* total gasto;
* variação percentual;
* distância percorrida;
* médias.

## IA interpreta

Exemplos:

> "Seu consumo caiu 12%."

> "Isso pode estar relacionado ao aumento de uso urbano."

A arquitetura:

**Dados do veículo**

↓

**Banco de dados**

↓

**Motor de cálculos/regras**

↓

**Contexto estruturado**

↓

**AI Service**

↓

**LLM**

↓

**Resposta**

---

# 16. AI Service

Não conectar todo o aplicativo diretamente ao Claude.

Criar uma camada abstrata:

```text
AIService
```

Possíveis providers:

```text
ClaudeProvider
GeminiProvider
OpenAIProvider
```

O restante do aplicativo conversa apenas com:

```text
AIService
```

Isso permite trocar de modelo no futuro sem reconstruir o sistema.

---

# 17. Modelo de IA inicial

A primeira opção a testar é **Claude Sonnet**.

Usar modelos mais caros/poderosos apenas quando necessário.

## Perguntas simples

Exemplo:

> "Quanto gastei esse mês?"

Não precisa de raciocínio pesado.

O backend calcula e a IA apenas apresenta.

## Perguntas complexas

Exemplo:

> "Por que meu consumo caiu nos últimos dois meses?"

Aqui a IA recebe:

* consumo histórico;
* quilometragem;
* abastecimentos;
* manutenção;
* padrão de utilização;
* alterações registradas.

E interpreta.

---

# 18. Não usar LLM para matemática

Exemplo:

Dados:

```text
distância = 500 km
combustível = 45 L
```

O backend calcula:

```text
consumo = 11,11 km/L
```

A IA recebe:

```text
Consumo atual: 11,11 km/L
Média histórica: 12,04 km/L
Variação: -7,7%
```

E transforma em linguagem natural.

Isso:

* reduz custo;
* reduz erros;
* aumenta confiabilidade.

---

# 19. Chat com IA

O usuário poderá conversar sobre o próprio veículo.

Exemplos:

> "Quanto gasto por mês com gasolina?"

> "Meu consumo está piorando?"

> "Quando foi minha última troca de óleo?"

> "O que preciso revisar?"

> "Meu carro está caro de manter?"

> "Quanto gastei com manutenção esse ano?"

> "Por que meu consumo aumentou?"

A IA deve responder utilizando os dados do usuário.

---

# 20. IA proativa

Não depender exclusivamente do usuário abrir o chat.

Exemplo:

> ⚠️ **Detectamos uma alteração**
>
> Seu consumo caiu de 10,8 km/L para 9,4 km/L.
>
> Isso representa uma queda de 13%.
>
> Quer que eu analise seu histórico?

Outro:

> 🔧 **Sua revisão está se aproximando**
>
> Seu veículo está chegando aos 90.000 km.
>
> Existem itens importantes para verificar nessa faixa.
>
> **[Ver recomendações]**

---

# 21. Confiança das informações

Todas as informações derivadas devem possuir algum nível de confiabilidade quando relevante.

### Alta

Dados objetivos e completos.

### Média

Estimativa baseada em histórico.

### Baixa

Poucos dados ou dados inconsistentes.

Isso deve ser utilizado especialmente em:

* consumo;
* previsão;
* manutenção;
* anomalias.

---

# 22. Banco de dados inicial

Sugestão de estrutura:

## users

* id
* email
* created_at

## vehicles

* id
* user_id
* brand
* model
* version
* year
* engine
* fuel_type
* current_odometer
* created_at

## refuels

* id
* vehicle_id
* date
* odometer
* liters
* price_per_liter
* total_price
* fuel_type
* full_tank
* station_name
* latitude
* longitude
* created_at

## maintenance

* id
* vehicle_id
* type
* date
* odometer
* cost
* description
* establishment
* created_at

## maintenance_rules

* id
* vehicle_model
* version
* engine
* maintenance_type
* interval_km
* interval_months
* notes

## ai_conversations

* id
* user_id
* vehicle_id
* created_at

## ai_messages

* id
* conversation_id
* role
* content
* created_at

Essa estrutura pode evoluir conforme o desenvolvimento.

---

# 23. Stack inicial sugerida

## Mobile

**Flutter**

Motivo:

* Android + iOS;
* uma codebase;
* bom ecossistema;
* adequado para MVP;
* boa integração com APIs, localização e Bluetooth futuramente.

## Backend

**Supabase**

Utilizar inicialmente:

* PostgreSQL;
* Authentication;
* Storage;
* Edge Functions, quando necessário.

## Banco

**PostgreSQL**

## Código

**GitHub**

## Desenvolvimento

**VS Code**

## IA para desenvolvimento

Primeira opção:

**Claude Code**

Alternativa gratuita:

**Gemini Code Assist**

---

# 24. Integração futura OBD2

Não faz parte do MVP.

Possível arquitetura:

**Veículo**

↓

**OBD2**

↓

**Bluetooth**

↓

**Aplicativo**

↓

**Dados do veículo**

Possíveis dados:

* nível de combustível;
* RPM;
* velocidade;
* temperatura;
* parâmetros do motor;
* códigos de falha;
* dados de consumo quando suportados.

A disponibilidade dependerá do veículo.

Não criar hardware próprio inicialmente.

---

# 25. FIPE

Funcionalidade futura.

Mostrar:

* valor de referência;
* evolução;
* desvalorização.

Exemplo:

> FIPE atual: R$ 78.430

> 12 meses atrás: R$ 83.100

> Variação: -5,6%

---

# 26. Custo total

Futuramente:

### Combustível

R$ X

### Manutenção

R$ X

### Impostos

R$ X

### Seguro

R$ X

### Outros

R$ X

### Total

**R$ X/mês**

Também:

> **R$ X por km**

---

# 27. Foto de comprovante

Futuro.

Usuário tira foto da nota.

IA extrai:

* serviço;
* peças;
* valor;
* data;
* quilometragem.

Transforma automaticamente em registro.

Objetivo:

**reduzir digitação.**

---

# 28. Monetização

## V1

Aplicativo gratuito.

Monetização através de anúncios discretos.

Objetivo:

**pagar custos e validar o produto.**

Não colocar anúncios em momentos críticos.

---

# 29. Premium

Depois de provar retenção.

Possível preço:

**R$ 9,90–R$ 14,90/mês**

Benefícios possíveis:

* sem anúncios;
* IA avançada;
* análises avançadas;
* alertas inteligentes;
* previsões;
* múltiplos veículos;
* histórico completo;
* relatórios;
* leitura de documentos;
* integração OBD2;
* recursos avançados.

O preço deverá ser validado.

---

# 30. Aquisição inicial

Não depender inicialmente de anúncios pagos.

Criar:

* cartões;
* adesivos;
* QR Codes.

Distribuir em:

* postos;
* lavações;
* oficinas;
* lojas automotivas;
* estacionamentos.

Mensagem:

> **Você sabe quanto seu carro realmente custa?**
>
> Controle combustível, consumo e manutenção em um só lugar.
>
> **Baixe grátis.**

---

# 31. Estratégia de validação

Primeiro objetivo:

**50–100 usuários reais.**

Período:

**30–60 dias.**

Acompanhar:

* cadastro;
* primeiro abastecimento;
* segundo abastecimento;
* retorno em 7 dias;
* retorno em 30 dias;
* retorno em 60 dias;
* uso da IA;
* ativação de localização;
* registros de manutenção.

---

# 32. Métrica principal

A métrica mais importante inicialmente não é:

> downloads.

É:

> **retenção.**

Pergunta principal:

> "As pessoas continuam usando depois que a novidade passa?"

---

# 33. Hipótese de retenção

O aplicativo precisa criar vários motivos para retornar:

### Abastecimento

📍 Detecção de posto.

### Manutenção

🔧 Alertas.

### Consumo

📊 Evolução.

### Gastos

💰 Fechamento mensal.

### Veículo

📉 Valorização.

### IA

🤖 Perguntas e análises.

Assim, mesmo que o usuário passe semanas sem abastecer, o aplicativo continua tendo utilidade.

---

# 34. Principal risco

## O aplicativo virar um diário que o usuário abandona.

Evitar depender de:

> "Abra o app e preencha tudo."

Priorizar:

* automação;
* localização;
* IA;
* notificações;
* importação;
* reconhecimento de documentos;
* OBD2 futuro.

---

# 35. Regra de produto

Sempre perguntar:

> **"Essa funcionalidade faz o aplicativo trabalhar mais e o usuário trabalhar menos?"**

Se sim:

**alta prioridade.**

Se adiciona apenas mais campos para preencher:

**baixa prioridade.**

---

# 36. Roadmap

## Fase 1 — Fundação

* [ ] Criar repositório GitHub
* [ ] Criar projeto Flutter
* [ ] Criar projeto Supabase
* [ ] Configurar banco
* [ ] Configurar autenticação
* [ ] Configurar ambientes
* [ ] Criar estrutura inicial do aplicativo

## Fase 2 — Veículo

* [ ] Cadastro
* [ ] Edição
* [ ] Visualização
* [ ] Quilometragem

## Fase 3 — Abastecimento

* [ ] Cadastro
* [ ] Histórico
* [ ] Edição
* [ ] Exclusão
* [ ] Tanque cheio/parcial
* [ ] Cálculo de preço/litro
* [ ] Algoritmo de consumo

## Fase 4 — Dashboard

* [ ] Consumo
* [ ] Gastos
* [ ] Quilometragem
* [ ] Histórico
* [ ] Próximas manutenções

## Fase 5 — Manutenção

* [ ] Cadastro
* [ ] Histórico
* [ ] Lembretes
* [ ] Regras básicas

## Fase 6 — Localização

* [ ] Permissão de localização
* [ ] Identificação de postos
* [ ] Notificação
* [ ] Registro rápido

## Fase 7 — IA

* [ ] AIService
* [ ] Provider
* [ ] Contexto do veículo
* [ ] Chat
* [ ] Perguntas sobre histórico
* [ ] Análises
* [ ] Respostas com dados reais

## Fase 8 — Beta

* [ ] Testes
* [ ] Correção de bugs
* [ ] Analytics
* [ ] Testes com usuários
* [ ] Ajustes de UX

## Fase 9 — Publicação

* [ ] Google Play
* [ ] App Store
* [ ] Landing page
* [ ] QR Codes
* [ ] Cartões

---

# 37. Pós-MVP

Depois de validar retenção:

* [ ] FIPE
* [ ] múltiplos veículos
* [ ] custo total
* [ ] leitura de notas
* [ ] IA mais avançada
* [ ] Premium
* [ ] anúncios
* [ ] OBD2
* [ ] oficinas
* [ ] parceiros
* [ ] marketplace
* [ ] seguros/serviços
* [ ] hardware opcional

---

# 38. Arquitetura conceitual

```text
                    USUÁRIO
                       │
                       ▼
               ┌───────────────┐
               │  FLUTTER APP  │
               └───────┬───────┘
                       │
                       ▼
               ┌───────────────┐
               │    SUPABASE   │
               │               │
               │ PostgreSQL    │
               │ Auth          │
               │ Storage       │
               └───────┬───────┘
                       │
          ┌────────────┼─────────────┐
          │            │             │
          ▼            ▼             ▼
      ABSTEC.      MANUTENÇÃO    VEÍCULO
          │            │             │
          └────────────┼─────────────┘
                       ▼
               MOTOR DE REGRAS
                       │
             ┌─────────┴─────────┐
             ▼                   ▼
        CÁLCULOS             CONTEXTO
        PRECISOS            DO VEÍCULO
             │                   │
             └─────────┬─────────┘
                       ▼
                   AI SERVICE
                       │
             ┌─────────┴─────────┐
             ▼                   ▼
          SONNET                OPUS
                       │
                       ▼
                  RESPOSTA IA
```

---

# 39. Princípio técnico

## O banco guarda fatos.

Exemplo:

> "Usuário abasteceu R$ 100."

## O backend calcula.

Exemplo:

> "Consumo médio = 10,7 km/L."

## A IA interpreta.

Exemplo:

> "Seu consumo caiu 8% em relação à média histórica."

Essa separação deve ser mantida desde o início.

---

# 40. Princípio de segurança da IA

A IA não deve:

* inventar especificações;
* afirmar diagnóstico mecânico definitivo;
* apresentar estimativas como certezas;
* substituir um mecânico;
* executar ações críticas sem confirmação.

Quando necessário:

> "Isso pode indicar X, mas é recomendável avaliação profissional."

---

# 41. Objetivo da V1

A V1 não precisa ser perfeita.

Ela precisa responder:

> **"Uma pessoa comum consegue cadastrar o carro, registrar seus abastecimentos e perceber valor suficiente para continuar utilizando o aplicativo?"**

Se a resposta for sim:

**continuar.**

Se a resposta for não:

**descobrir por quê antes de adicionar funcionalidades.**

---

# 42. Objetivo de longo prazo

Construir uma plataforma em que o usuário possa pensar:

> **"Eu não preciso lembrar de tudo sobre meu carro. Meu aplicativo lembra por mim."**

O produto começa com:

**abastecimento**

↓

evolui para:

**consumo**

↓

**manutenção**

↓

**gastos**

↓

**valor**

↓

**IA**

↓

**automação**

↓

**OBD2**

↓

**assistente automotivo completo.**

---

# 43. Primeira tarefa de desenvolvimento

Não começar criando telas aleatoriamente.

A primeira sequência recomendada é:

1. Definir arquitetura.
2. Criar repositório.
3. Configurar Flutter.
4. Configurar Supabase.
5. Criar banco.
6. Criar autenticação.
7. Criar cadastro de veículo.
8. Criar abastecimento.
9. Implementar algoritmo de consumo.
10. Criar dashboard.
11. Criar manutenção.
12. Criar localização.
13. Criar AIService.
14. Integrar primeiro modelo.
15. Testar com usuários reais.

---

# 44. Regra para trabalhar com IA de programação

Não pedir para a IA gerar o aplicativo inteiro.

Trabalhar por etapas.

Exemplo:

> "Analise a arquitetura atual. Não escreva código ainda. Identifique problemas."

Depois:

> "Implemente apenas o cadastro de veículos."

Depois:

> "Escreva testes para o cadastro."

Depois:

> "Implemente o algoritmo de consumo."

Depois:

> "Crie testes cobrindo abastecimentos completos, parciais e registros esquecidos."

A IA deve funcionar como um **desenvolvedor sênior auxiliar**, não como um gerador de código aleatório.

---

# 45. Visão final

O aplicativo não deve ser lembrado como:

> "aquele app de gasolina."

Deve ser lembrado como:

> **"o aplicativo que conhece meu carro."**

Essa é a visão que deve orientar todas as decisões de produto, design e desenvolvimento.
