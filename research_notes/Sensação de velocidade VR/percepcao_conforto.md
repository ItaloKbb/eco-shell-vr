# Percepção de velocidade, presença e conforto em VR veicular

## Quais pistas perceptuais têm maior efeito na velocidade percebida em HMDs?

### Takeaway
O fluxo óptico de expansão no campo periférico e inferior — sobretudo produzido por detalhes próximos ao veículo — é a pista visual mais forte para auto-movimento e velocidade. Estereopsia, pequenas oscilações coerentes, áudio dependente de velocidade/RPM e vibração congruente reforçam a sensação sem exigir aumento da velocidade física simulada, mas as mesmas pistas visuais fortes também podem elevar o enjoo.

### Cited Findings
- Em uma simulação passiva de direção em HMD, 120 mph em vez de 60 mph elevou significativamente tanto vection quanto motion sickness; fluxo em expansão (movimento para frente) gerou mais vection, sickness e presença que fluxo em contração ou lateral. É evidência direta, recente e específica a veículos, embora baseada em voltas pré-gravadas de 60 s e não em controle ativo — [Hughes, Naeem & Davidenko, Scientific Reports 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC11618617/).
- Em HMD, movimento em profundidade produziu vection mais forte que movimento lateral; para movimento em profundidade, padrões mais periféricos produziram vection mais forte e a periferia extrema elevou desconforto. Logo, periferia é simultaneamente uma alavanca de velocidade e uma zona de risco — [Palmisano et al., Perception 2021](https://pubmed.ncbi.nlm.nih.gov/33882451/).
- Fluxo óptico no campo visual inferior gerou maior deslocamento da cabeça e vection que no campo superior, consistente com a importância ecológica do chão para controle postural e auto-movimento — [Tamada & Seno, Multisensory Research 2020](https://pubmed.ncbi.nlm.nih.gov/31803463/).
- Estereopsia global mais fraca reduziu vection e presença e também reduziu cybersickness; portanto, profundidade binocular fortalece o auto-movimento, mas existe um trade-off de conforto — [Kim et al., Virtual Reality 2022](https://pubmed.ncbi.nlm.nih.gov/34117273/).
- Oscilação e jitter de viewpoint podem fortalecer vection; ao igualar velocidade percebida, a vantagem de oscilação desapareceu, enquanto a de jitter permaneceu, sugerindo mecanismos distintos. Isso apoia microcues com cautela, não camera shake arbitrário — [Palmisano et al., Experimental Brain Research 2014](https://pubmed.ncbi.nlm.nih.gov/24651861/).
- Em locomoção virtual, densidade de objetos altera velocidade percebida; o estudo encontrou relação mais linear em densidade moderada, advertindo que simplesmente saturar a cena com partículas não garante resposta previsível — [Dorado et al., Eurographics 2024](https://diglib.eg.org/bitstreams/dfbc32d2-cd17-4d2a-8edf-e45547d323fa/download).
- Som do motor é uma pista funcional de velocidade: em simulador, condições sem som ou com 65–70 dB(A) levaram a velocidades escolhidas maiores que 75–85 dB(A), indicando subestimação/menor saliência da velocidade quando o feedback sonoro é reduzido. Os valores absolutos não devem ser transplantados diretamente para fones de HMD — [Hellier et al., Transportation Research Part F 2011](https://doi.org/10.1016/j.trf.2011.07.004).
- Som que representa auto-movimento pode reforçar vection linear; o resultado é evidência clássica de integração audiovisual, mas não fornece uma receita moderna de mixagem para jogos — [Riecke et al., 2009](https://research.chalmers.se/en/publication/99346).
- Vibração de piso minimamente coerente com um percurso off-road reduziu significativamente a subescala oculomotora do delta-SSQ e GSR, ambos com efeitos grandes, em relação a sem vibração; as demais variáveis apontaram na mesma direção, mas com efeitos pequenos/triviais. A amostra foi pequena (11+11) — [Jung et al., IEEE TVCG 2021](https://pubmed.ncbi.nlm.nih.gov/33760736/).
- Em um cockpit de corrida, sinais visuais, áudio e vibração aumentaram integração multissensorial e presença/desempenho conforme a carga da tarefa; trata-se de apoio à congruência multissensorial, não de um limiar universal de intensidade — [Grassini et al., Scientific Reports 2021](https://www.nature.com/articles/s41598-021-84196-8).

### Inferences
- **Prática consolidada:** aumentar *edge rate* perto do jogador — textura do asfalto com escala correta, marcas de pista, postes, vegetação e barreiras laterais espaçadas — deve produzir mais sensação de velocidade por unidade de velocidade real que enriquecer apenas o horizonte. Priorizar os quadrantes inferior e lateral, deixando centro/horizonte legíveis.
- **Hipótese de design a validar:** partículas world-space (poeira, folhas, respingos) que cruzem a periferia em rajadas curtas, ligadas a piso/vento/boost, podem gerar picos de velocidade percebida com menor exposição acumulada que um starfield contínuo. Devem nascer de fontes plausíveis e usar densidade moderada; screen-space streaks constantes podem parecer movimento da tela e aumentar conflito.
- **Prática consolidada:** mapear pitch, espectro, volume e vento ao RPM/carga/velocidade, com transientes distintos para aceleração e troca de marcha. A pista deve ser monotônica e previsível; loudness excessivo não é necessário nem seguro.
- **Hipótese de design a validar:** vibração de controle/assento de baixa amplitude, sincronizada com motor, textura do piso e impactos, pode aumentar presença e, se congruente, reduzir parte do conflito. Vibração genérica constante provavelmente perde valor informacional.

### Gaps
- Não foi encontrado um ranking quantitativo universal que compare, no mesmo experimento de corrida em HMD, fluxo óptico, áudio, háptica, partículas e escala do cenário.
- Não há um valor universal de densidade/tamanho/velocidade de partículas que maximize velocidade percebida sem elevar cybersickness; os resultados dependem de FOV do headset, contraste, tempo de exposição e suscetibilidade individual.

## Quais técnicas aumentam cybersickness e quais mitigam?

### Takeaway
As provocações mais consistentes são rotação visual não acompanhada pelo corpo, acelerações repetidas/irregulares, fluxo periférico forte, pitch/roll/camera shake impostos, baixa estabilidade de frame e movimento não antecipável. Mitigam: horizonte/vertical terrestre estável, cockpit como referência, movimento previsível e controlável, transições com jerk limitado, cues hápticos/sonoros congruentes, vinheta opcional e adaptação gradual.

### Cited Findings
- Um horizonte fixo à Terra reduziu significativamente VIMS, mas uma cruz fixa à Terra e uma linha presa à cabeça não; o benefício foi modesto e dependeu de comunicar horizontalidade, não apenas de oferecer um ponto estacionário — [Hemmerich, Keshavarz & Hecht, Frontiers in Virtual Reality 2020](https://www.frontiersin.org/journals/virtual-reality/articles/10.3389/frvir.2020.582095/full).
- Limiares de início de cybersickness para fluxo óptico rotacional foram significativamente menores que para fluxo translacional, com grande variabilidade entre pessoas; os autores recomendam ajuste individual em vez de um único valor médio — [Terenzi & Zaal, AIAA SciTech/NASA 2020](https://ntrs.nasa.gov/citations/20200000787).
- Velocidade constante tendeu a ser mais confortável que perfis de velocidade variável; a literatura de projeto recomenda manter acelerações curtas e infrequentes — [Harrington et al., Human Factors 2021](https://pubmed.ncbi.nlm.nih.gov/31651196/).
- Um perfil *minimum-jerk* com restrições de velocidade, aceleração e jerk reduziu cybersickness/produziu navegação mais natural e confortável; tanto magnitude de aceleração quanto jerk afetaram experiência — [Chardonnet et al., International Journal of Human-Computer Studies 2021](https://doi.org/10.1016/j.ijhcs.2020.102578).
- Em jogo de corrida VR (N=32), redução dinâmica de FOV, blur de profundidade e retículo como rest frame não diferiram significativamente em sickness, presença ou workload. FOV dinâmico e blur causaram perda de informação; mudanças frequentes de FOV durante aceleração/curvas causaram desconforto em alguns participantes — [Shi et al., PACMCGIT 2021](https://doi.org/10.1145/3451255).
- Restrição periférica pode reduzir o estímulo que produz vection, mas também pode reduzir presença e informação; seu efeito não é uniforme entre tarefas e pessoas — [Teixeira & Palmisano, Virtual Reality 2021](https://doi.org/10.1007/s10055-020-00425-3).
- Exposição gradual a contraste/força crescente de fluxo óptico reduziu sickness ao longo de dias, e a adaptação transferiu de ambiente abstrato para realista — [Adhanom et al., Frontiers in Virtual Reality 2023](https://pubmed.ncbi.nlm.nih.gov/36873792/).
- O guia oficial da Meta recomenda limitar duração e frequência de aceleração, reduzir fluxo periférico, manter frame rate consistente, fornecer backgrounds independentes e oferecer perfis Recommended/Comfortable/Advanced — [Meta, Locomotion Best Practices, atualizado em 2025](https://developers.meta.com/vr/design/locomotion-best-practices/).

### Inferences
- **Recomendação forte:** nunca adicionar pitch, roll, yaw, head bob ou camera shake diretamente à pose da `XRCamera3D`. A pose real da cabeça deve continuar 1:1; efeitos de veículo devem atuar no mundo/cockpit ao redor dela ou em um rig intermediário cuidadosamente filtrado.
- **Recomendação forte:** manter um horizonte gravitacional legível e oferecer *horizon lock* graduável. Uma opção útil é separar movimentos: cockpit absorve parte da suspensão/roll, enquanto o horizonte permanece mais estável; expor intensidade em vez de impor uma solução única.
- **Prática consolidada:** vinheta/tunneling deve ser overlay ou máscara de conforto, acionada por magnitude de velocidade angular/aceleração e com ataque/relaxamento suaves; não alterar o FOV/projeção estéreo física. Deve ser opcional, pois pode reduzir visão lateral essencial em corrida.
- **Limitação OpenXR:** `xrLocateViews` fornece, a cada frame e para o tempo previsto de display, a pose e os parâmetros de projeção/FOV ideais de cada olho. Substituí-los como se fosse uma câmera plana pode quebrar a correspondência óptica/estéreo; a forma segura de conforto é compor uma vinheta dentro das views recomendadas — [Khronos OpenXR 1.1, View and Projection State](https://registry.khronos.org/OpenXR/specs/1.1-khr/html/xrspec.html#view_configuration).
- **Recomendação forte:** usar perfis de velocidade com derivadas contínuas, evitar alternância repetida de acelera/freia e dar antecedência sonora/visual antes de boost, curva fechada, queda ou colisão. Em acidentes/capotamentos, oferecer corte, fade ou estabilização automática.
- **Prática consolidada:** medir continuamente frame time e quedas/reprojeção; priorizar estabilidade sobre picos de qualidade. Preservar head tracking de baixa latência é requisito de conforto, não um efeito estético.

### Gaps
- Os estudos não convergem para limites numéricos universais de velocidade, aceleração ou jerk em VR. Os valores variam com eixo, campo visual, densidade visual, duração e indivíduo; os limiares NASA são para campo de partículas e não devem ser copiados para um carro completo.
- A evidência comparativa de *horizon lock* parcial versus cockpit lock em corridas comerciais permanece escassa; é necessário teste A/B no conteúdo real.

## O que muda em cockpit seated versus locomoção livre?

### Takeaway
O cockpit seated oferece um referencial egocêntrico plausível, suporte postural e expectativa semântica de deslocamento, portanto tolera velocidades translacionais maiores que locomoção livre. Em contrapartida, curvas, inclinações e acelerações visuais ainda conflitam com um corpo estacionário; controle ativo e antecipação importam, e passenger/autodrive tende a ser mais provocativo.

### Cited Findings
- Em comparação postura×locomoção, joystick em pé aumentou instabilidade postural; sentado+teleporte apresentou menos cybersickness. Isso sustenta o benefício postural do assento, mas o paradigma não era corrida — [Lee et al., International Journal of Human–Computer Interaction 2024](https://doi.org/10.1080/10447318.2023.2250611).
- Em direção VR, dirigir ativamente aumentou presença em relação a ser copiloto; o estudo não encontrou efeito igualmente claro de interatividade sobre sickness, portanto controle não deve ser tratado como proteção garantida — [Sportillo et al., Frontiers in Virtual Reality 2024](https://www.frontiersin.org/journals/virtual-reality/articles/10.3389/frvir.2024.1484739/full).
- Controle de veículo virtual reduziu risco de motion sickness em um experimento yoked driver/passenger com crianças; a generalização a adultos e HMDs de corrida deve ser cautelosa — [Stoffregen et al., Human Movement Science 2021](https://doi.org/10.1016/j.humov.2021.102760).
- Em VR livre, teleporte causou menos náusea que joystick e leaning, sem diferença significativa de presença; em corrida, teleporte não é semanticamente aplicável, mas o resultado evidencia o custo do fluxo contínuo sem cues corporais — [Bozgeyikli et al., IEEE TVCG 2019](https://pubmed.ncbi.nlm.nih.gov/31329560/).
- O conceito de `LOCAL` em OpenXR é gravity-aligned e explicitamente apropriado a conteúdo seated-scale; `VIEW` é adequado apenas a conteúdo pequeno preso à cabeça, que pode ficar desconfortável se grande — [Khronos OpenXR 1.1, Reference Spaces](https://registry.khronos.org/OpenXR/specs/1.1-khr/html/xrspec.html#spaces-reference-spaces).

### Inferences
- **Cockpit seated:** manter painel, para-brisa, coluna A e capô em escala 1:1 e world-/vehicle-space, permitindo parallax natural da cabeça. Eles devem funcionar como rest frame plausível, não como HUD colado ao HMD.
- **Cockpit seated:** priorizar pistas lineares para frente e minimizar rotação visual artificial. Usar volante/mãos/controle responsivo, som antecipatório e feedback de superfície para aumentar agência e previsibilidade.
- **Locomoção livre:** velocidades equivalentes são muito mais provocativas porque não há estrutura veicular nem postura congruente; oferecer teleporte/snap turn, velocidade de caminhada realista e movimento físico quando possível.
- **Passenger/autodrive/cutscene:** tratar como modo de maior risco. Reduzir aceleração/curvatura, mostrar trajeto/horizonte, avisar manobras e oferecer skip/fade.

### Gaps
- A vantagem exata do cockpit depende de quanto ele ocupa da periferia e se acompanha carro, horizonte ou cabeça; não há uma geometria padronizada validada para todos os HMDs.
- A literatura driver-versus-passenger mistura veículos reais, telas, CAVEs e HMDs; o efeito de agência sobre sickness em HMD seated ainda é menos consistente que seu efeito sobre presença.

## Existem faixas, thresholds ou princípios de calibração úteis?

### Takeaway
Não existe um conjunto de thresholds universais e seguro para um carro VR. O melhor estado da arte é calibração psicofísica e incremental por eixo/efeito, com perfis de conforto, telemetria de desempenho e testes de sintomas; rotação merece limites mais conservadores que translação.

### Cited Findings
- Os limiares de cybersickness medidos por Terenzi & Zaal tiveram alta variabilidade individual e correlação entre eixos; rotação foi provocativa em intensidades menores que translação. Os autores defendem tuning individual — [NASA/AIAA 2020](https://ntrs.nasa.gov/citations/20200000787).
- O guia Meta usa 1,4 m/s como velocidade média de caminhada e aproximadamente o dobro para corrida em locomoção livre; esses números não são limites para veículos, mas mostram por que velocidades de console aplicadas a um avatar humano geram fluxo excessivo — [Meta, Reduce Optic Flow, 2026](https://developers.meta.com/vr/resources/locomotion-design-reduce-optic-flow/).
- A adaptação gradual a fluxo óptico crescente reduziu sickness entre dias, apoiando uma progressão de intensidade em tutorial e sessões, e não exposição agressiva imediata — [Adhanom et al., 2023](https://pubmed.ncbi.nlm.nih.gov/36873792/).
- O SSQ continua sendo medida estabelecida, mas vection, presença e sickness não mantêm uma relação simples: um modelo sensorimotor explicou 37% da variação de cybersickness, e vection autorrelatada não foi preditor significativo nesse estudo — [Weech et al., Journal of Neurophysiology 2018](https://pubmed.ncbi.nlm.nih.gov/30044672/).

### Inferences
- **Procedimento recomendado para Godot/OpenXR:** criar variáveis independentes e telemetradas para (1) velocidade física do carro, (2) densidade/contraste de near-field, (3) partículas, (4) ganho de áudio, (5) háptica, (6) horizon lock, (7) atenuação de suspensão e (8) vinheta. Não juntar tudo em um único slider de “intensidade”.
- **Ordem de calibração:** primeiro garantir escala/IPD/pose e frame pacing; depois estabilizar horizonte e cockpit; depois ajustar perfil aceleração–jerk; por fim adicionar fluxo próximo, áudio, háptica e partículas em passos pequenos.
- **Matriz mínima de teste:** retas versus curvas; baixa versus alta velocidade; asfalto versus off-road; driver versus passenger; novato versus usuário experiente. Medir FMS durante a volta, SSQ/VRSQ antes/depois, presença, velocidade percebida, abandonos e frame-time/reprojeção.
- **Critério prático:** se um cue aumenta velocidade percebida sem aumentar FMS/SSQ e sem degradar detecção lateral, mantê-lo; se o ganho exige rotação de câmera ou fluxo periférico contínuo, movê-lo para perfil Advanced e fornecer alternativa Comfortable.
- **Perfis iniciais, como hipótese de produto:** Comfortable = horizon lock alto, suspensão visual baixa, partículas/near-field reduzidos, vinheta adaptativa e aceleração suave; Recommended = referência estável com cues multissensoriais moderados; Advanced = fluxo/roll/cues fortes, ainda sem adulterar pose da cabeça ou projeção OpenXR.

### Gaps
- Não há base científica suficiente para prescrever, sem teste local, graus de horizon lock, raio/opacidade de vinheta, m/s² ou m/s³ específicos para este jogo.
- Valores de conforto de veículos físicos/ISO não podem ser convertidos diretamente em limites visuais de uma plataforma VR estacionária; a entrada vestibular é diferente.
