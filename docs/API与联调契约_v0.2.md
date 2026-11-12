# API 与联调契约 v0.2

更新日期为 2026-11-08。B 统一发布本契约，D、E 按完整功能实现并联调。

本文是可实施的接口初稿。方法名、数据语义、初值和首轮提供方已填写，技术实现随 B 的基线评审确认。当前交付形式为设计文档，C# 接口源文件在实现任务中生成。

玩法规则和数值引用[灰盒设计 v0.2](灰盒设计_v0.1.md)，素材编号和具体交付引用 [B 的统筹交付总表](交接/B_策划_API与协调.md)。

## 1. 提供方与消费方

| 接口 | 首轮提供方 | 消费方 | 职责 |
|---|---|---|---|
| IPlayerService | D | 交互、镜头、车辆、HUD | 人物输入、状态、身体和关联 |
| IInteractionService | D | 人物、HUD、物理对象 | 多人抓取、目标、松手及力贡献计算 |
| IPhysicsObjectService | E | 交互、车辆、交付、网络适配 | 物体属性、物理状态和共同作用汇总 |
| IVehicleService | E | 人物、镜头、HUD、交互 | 座位、驾驶、固定与释放 |
| ICameraContextService | D | 座位事件、场景触发、本地表现 | 条件式镜头上下文 |
| IHandbookService | D | 人物生成、HUD、输入 | 开局手册和重复查看 |
| IRoundService | E | 会话、HUD、物体生命周期 | 送货计数、阶段、完成和重置 |
| ISessionService | D | 两个功能包 | 玩家映射、操作投递、状态传播与断线通知 |

首轮实际契约源文件建议放入 who-sent-this-guy/shared/contracts，使用命名空间 DeliveryGame.Contracts。B 维护对外定义和版本，D 负责首次接入工程，D、E 的具体服务可以各自独立组织内部文件。

## 2. 公共单位、标识与命令结果

### 2.1 公共类型

| 类型 | 字段与约束 |
|---|---|
| CommandKey | uint RoundEpoch、ulong PlayerId、ulong RequestId、ulong InputTick。请求编号在玩家连接期间递增，连续输入每个样本使用新编号 |
| PoseState | Vector3 PositionM、Quaternion Rotation、Vector3 LinearVelocityMps、Vector3 AngularVelocityRadps、ulong StateTick、uint Revision |
| CommandResolution | CommandKey Key、ResultCode Code、ulong TargetId、uint Revision。表示统一裁决后的结果 |
| PlayerSnapshot | ulong PlayerId、uint RoundEpoch、PoseState Pose、LifeState LifeState、LocomotionMode LocomotionMode、Stance Stance、ulong? HeldCargoId、ulong? SeatedVehicleId、string? SeatId、float BodyMassKg |
| GripParticipant | ulong PlayerId、ulong CargoId、Vector3 LocalPointM、Vector3 TargetPositionM、Quaternion TargetRotation、GripMode Mode、ulong LastInputTick |
| CargoSnapshot | ulong EntityId、string DefinitionId、PoseState Pose、float MassKg、string SurfaceId、GripParticipant[] Participants、ulong? SecuredVehicleId、bool Delivered、uint RoundEpoch |
| VehicleSnapshot | ulong EntityId、PoseState Pose、float SpeedMps、float RollDeg、float LoadMassKg、float OccupantMassKg、float TransportedSystemMassKg、float VehicleRigidBodyMassKg、Vector3 EffectiveCenterOfMassLocalM、float EngineLoad01、float SkidIntensity01、SeatSnapshot[] Seats、uint RoundEpoch |
| SeatSnapshot | string SeatId、ulong? OccupantPlayerId、Transform3D SeatTransform、Transform3D[] ExitCandidates |
| RoundSnapshot | uint RoundEpoch、RoundPhase Phase、ulong[] DeliveredCargoIds、int RequiredCount、double ElapsedSeconds |
| ForceContribution | uint RoundEpoch、ulong PhysicsTick、ulong PlayerId、ulong EntityId、ContributionKind Kind、Vector3 LocalPointM、Vector3 ForceWorldN |
| GameplayEvent | ulong EventId、uint RoundEpoch、ulong StateTick、string Kind、ulong SourceEntityId、ulong ActorPlayerId、Vector3 PositionM、string SurfaceId、float Intensity01 |

实际 C# 记录结构使用表中字段对应的明确定义类型。可空对象关联采用 nullable ID，字符串类型用于 B 登记的定义名和座位名。公开状态为只读快照，数组由提供方保护其内部状态。

长度 m、质量 kg、时间 s、力 N、角速度 rad/s。方法名带 Rad 的观察输入为弧度增量，带 Deg 的展示值为角度。所有请求携带回合编号，实例标识在回合重置后重新映射。

InputTick 标识玩家输入样本，PhysicsTick 标识统一裁决端的物理更新。会话适配把有效输入映射到待执行的物理更新，再生成力贡献。物理步初始频率为 60 Hz，网络发布频率在 B 的标定批次确定。

### 2.2 枚举语义

| 类型 | 本版取值 |
|---|---|
| LifeState | Active、Recovering、Disconnected |
| LocomotionMode | OnFoot、Seated |
| Stance | Standing、Crouching |
| GripMode | SupportedCarry、PhysicalDrag |
| RoundPhase | Preparing、Loading、Transporting、Unloading、Completed、Resetting |
| CameraContextKind | DefaultFirstPerson、DrivingThirdPerson、LocationThirdPerson、PassengerFirstPerson |
| ContributionKind | Grip、BodyPush |
| ResultCode | Accepted、AlreadyApplied、InvalidRound、InvalidActor、TargetMissing、OutOfReach、Obstructed、HandsBusy、FixedCargo、GripFull、SeatOccupied、VehicleMoving、NoSafeExit、StateChanged、InvalidState |

Accepted 表示对应状态变化已由统一裁决端应用。Request 方法先投递意图，通过 CommandResolved 事件返回实际结果。网络延迟期间调用方可以显示处理中，收到结果后更新。

请求先检查回合和发送者，再处理幂等缓存，最后执行操作资格校验。相同 PlayerId、RequestId 的重复离散请求返回之前的结果，状态只应用一次。旧回合请求返回 InvalidRound。连续输入按 PlayerId 和输入流只保留最新有效样本，不能因重传累加受力。

网络状态消息统一携带 RoundEpoch、StateTick 和 Revision。接收端丢弃旧回合及过期版本，再更新本地只读状态并发出订阅事件。ParticipantsChanged 等事件为本地确认状态通知，网络适配使用带上述元数据的快照传播。

## 3. 人物服务

~~~csharp
void SubmitInput(CommandKey key, CharacterInput input);
PlayerSnapshot? ReadPlayer(ulong playerId);
event Action<PlayerSnapshot> PlayerChanged;
event Action<CommandResolution> CommandResolved;
~~~

CharacterInput 包含 Vector2 MoveAxis、Vector2 LookDeltaRad、bool SprintHeld、bool CrouchHeld、bool JumpPressed。移动轴长度裁剪到 1，人物速度、身体和跳跃初值取灰盒主文档。

| 输入或状态 | 明确行为 |
|---|---|
| 地面 JumpPressed | Active、OnFoot、未抓持时允许起跳 |
| 蹲下或站起 | 站起前检测站立体积，受阻维持蹲姿 |
| 正在抓持 | 移动速度取姿态速度与携物上限的较小值 |
| Seated | 身体遵循座位关联，步行输入按驾驶或乘员上下文处理 |
| 手册全屏 | 本地步行、视线和交互输入被手册消费，发送中性移动输入，重力和世界继续更新 |
| 越界恢复 | 先移除自己的抓持和座位关系，再移动到安全恢复点 |

人物身体推动刚体时，使用第 5 节的 BodyPush 贡献入口，由统一物理端执行。人物 80 kg 质量贡献和乘车方式与 E 的车辆实现共同接入 B 的采用方案。

## 4. 共同抓取服务

~~~csharp
void RequestGrab(CommandKey key, ulong cargoId, Vector3 localPointM);
void RequestRelease(CommandKey key, ulong cargoId);
void SubmitGripTarget(CommandKey key, ulong cargoId,
    Vector3 positionWorldM, Quaternion rotationWorld);
GripParticipant[] ReadParticipants(ulong cargoId);
event Action<ulong, GripParticipant[]> ParticipantsChanged;
event Action<CommandResolution> CommandResolved;
~~~

### 4.1 加入与退出

| 请求 | 检查 | 结果 |
|---|---|---|
| RequestGrab | 玩家 Active、空手、未坐入座位，对象有效、未固定，命中点可达且无遮挡 | 在现有参与列表中追加该玩家，保留已有参与者，人数上限为 2 |
| 已有参与者再次请求加入 | 同玩家已经关联该对象 | 返回 AlreadyApplied，保持当前参与关系 |
| 玩家已有另一抓持对象 | 检查人物关联 | 返回 HandsBusy |
| 第三名玩家加入 | 参与列表已满 | 返回 GripFull |
| RequestRelease | 玩家确实属于该物体参与列表 | 仅移除该玩家，其他人继续，重新计算模式 |
| 玩家断线、对象销毁或回合重置 | 生命周期事件 | 清理相应关系并广播参与者变化 |

相同请求的幂等结果先于资格检查处理。新请求若玩家已经参与同一物体，也先返回 AlreadyApplied；随后才检查 HandsBusy 等新加入资格。成功加入时，目标初始位置取抓点的当前世界位置，之后连续接入玩家目标，避免未初始化目标造成突变。

距离和模式采用人物属性。超距持续 0.2 s 后释放超距者。松手保持物体当前世界速度。

### 4.2 力贡献和搬运模式

每个物理更新读取物体的同一份已确认状态，分别计算每名参与者在自己局部抓点的作用。抓点速度包含刚体线速度和角速度在该点的贡献。

B 的初始抓持算法采用弹簧阻尼辅助。刚度初值 900 N/m，阻尼初值 120 N·s/m。单人输出力先按灰盒中的拖拽或抱持上限限幅，再提交 E 的力贡献入口。参数属于标定种子值。

货物质量小于或等于有效参与者数乘以 35 kg 时，使用 SupportedCarry，并按参与人数均分该物体的重力补偿。其余采用 PhysicalDrag，依赖接触和参与者的作用移动。模式改变时使用 0.2 s 连续过渡，避免突然改变目标或速度。

目标朝向参与受限姿态辅助，实际碰撞和物体旋转继续生效。姿态辅助的扭矩上限在 B 的物理标定批次中确定。

### 4.3 同物体两人操作示例

| 步骤 | 确认结果 |
|---|---|
| P1 对 cargo_heavy_01 加入 | Participants 为 P1 |
| P2 对同一物体另一局部点加入 | Participants 为 P1、P2 |
| 同一更新两人提交目标 | 同时生成 P1 和 P2 的力贡献，物体合力与力矩包含两人 |
| P1 松手 | Participants 变为 P2，P2 继续生效 |
| P1 的旧松手消息重传 | 返回之前的结果，P2 保持参与 |

## 5. 物理对象服务与汇总

~~~csharp
CargoSnapshot? ReadCargo(ulong cargoId);
void AddForceContribution(ForceContribution contribution);
event Action<CargoSnapshot> CargoChanged;
event Action<GameplayEvent> GameplayEventRaised;
~~~

AddForceContribution 为已确认逻辑进入权威物理更新的内部服务入口，D 的交互和身体推动通过该入口贡献力。各客户端的原始请求先经过会话和交互验证。

每个物理更新的贡献去重键包含回合、更新编号、玩家、物体和贡献种类。同一键的最新有效值替换该键旧值，不同玩家的值同时保留。该更新执行完即清空贡献缓存，过期输入不能被持续施加。

E 在同一更新应用所有有效作用点的力，由刚体求解得到运动。合力为各力的向量和，合力矩为各作用点相对重心的力矩之和。接触、重力和固定关系同时参与。

车辆本身可以接收 BodyPush，驾驶力与该贡献共同作用于车辆。司机驾驶资格保持唯一，车辆仍能同时受到其他玩家和货物的物理影响。

## 6. 车辆服务

~~~csharp
void RequestEnterSeat(CommandKey key, ulong vehicleId, string seatId);
void RequestExitSeat(CommandKey key);
void SubmitDriveInput(CommandKey key, ulong vehicleId, DriveInput input);
void RequestSetSecured(CommandKey key, ulong cargoId,
    ulong vehicleId, bool secured);
VehicleSnapshot? ReadVehicle(ulong vehicleId);
event Action<VehicleSnapshot> VehicleChanged;
event Action<CommandResolution> CommandResolved;
~~~

DriveInput 包含 float ForwardAxis、float SteeringAxis、bool HandbrakeHeld。轴范围为 -1 至 1。ForwardAxis 小于 0 时先制动，前进速度小于 0.5 m/s 后才产生倒车请求。连续驾驶输入只接受当前 driver 占用者。

| 请求 | 成功条件与状态变化 | 失败结果 |
|---|---|---|
| 进入 driver/passenger | 空座位、玩家空手、位置可达，成功后人物 Seated，关联座位并触发相应镜头 | SeatOccupied、HandsBusy、OutOfReach、InvalidState |
| 退出座位 | 车速小于 0.5 m/s，候选退出点存在合法站立体积 | VehicleMoving、NoSafeExit |
| 固定货物 | 未抓持、位于有效车厢、相对车厢已稳定，成功后更新 SecuredVehicleId | OutOfReach、InvalidState、StateChanged |
| 解除固定 | 当前固定关系有效，转换后继承该位置的线速度和角速度贡献 | TargetMissing、StateChanged |
| 司机断线 | 清空其连续输入与座位占用，安全制动，广播空座位 | 生命周期处理 |

固定初稿稳定条件为相对车厢线速度小于 0.1 m/s、相对角速度小于 0.2 rad/s 持续 0.5 s。固定货物被抓取时返回 FixedCargo。相同目标状态的重复固定请求返回 AlreadyApplied。

合并质量或独立约束由 B 的技术批次确定。MassKg 为货物定义质量，LoadMassKg 为车厢有效承载货物之和，OccupantMassKg 为座位占用者体质量之和。TransportedSystemMassKg 等于空车质量加前两项，是诊断总质量。VehicleRigidBodyMassKg 是当前车身刚体的实际配置值，随采用的表示变化。EffectiveCenterOfMassLocalM 使用诊断整体的同一纳入范围。固定和乘员质量只通过采用方案产生一次动力学贡献。

## 7. 镜头与操作手册

### 7.1 本地镜头服务

~~~csharp
void EnterContext(string contextId, CameraContextKind kind, ulong focusId);
void ExitContext(string contextId);
CameraContextKind ReadActiveContext();
~~~

驾驶上下文 ID 使用 driving_加车辆标识，乘员上下文使用 passenger_加车辆标识，地点上下文使用 B 白名单中的地点 ID。驾驶或乘员座位上下文优先级为 100、地点 10、默认第一人称 0。同一玩家同时只有一个座位关联。同 ID 更新已有上下文，退出未知 ID 保持当前有效结果。

进入座位的确认状态驱动镜头改变。预测 UI 或操作请求发出本身不改变确认的座位占用。镜头效果仅属于各端本地呈现，世界位置与参与者状态通过共享状态维护。

当前地点白名单为空，普通行走和装卸采用第一人称。未来地点仅在 B 注册后启用 LocationThirdPerson。测试可以注册临时地点验证嵌套和恢复，正式灰盒场地保持白名单内容。

### 7.2 本地手册服务

~~~csharp
void GrantToLocalPlayer(ulong playerId);
void Open();
void Close();
bool IsOpen { get; }
~~~

GrantToLocalPlayer 在本地玩家首次生成后执行，保证该玩家可访问手册。首次生成自动打开，重复生成和重置保留入口与页码。四页正文由 B 的灰盒文档直接提供。

步行时全屏手册消费本地操作输入，驾驶时显示侧边简版并保留驾驶输入。Esc 可关闭当前手册。手册的按键文字来自动作绑定，F1 是初始绑定。

## 8. 回合、交付和事件

~~~csharp
RoundSnapshot ReadRound();
void RequestReset(CommandKey key);
event Action<RoundSnapshot> RoundChanged;
event Action<GameplayEvent> GameplayEventRaised;
event Action<CommandResolution> CommandResolved;
~~~

交付判定在物理端按灰盒第 8 节执行，界面消费结果。DeliveredCargoIds 为每回合去重集合，RequiredCount 为 6。重置由已配置的调试或关卡入口发出，回合编号增加，旧命令拒绝，清理抓取、座位、固定、计数和持续音效。

| GameplayEvent.Kind | 触发与字段 | 声音或反馈 |
|---|---|---|
| CargoGrabbed | 每名参与者成功加入时，SourceEntityId 为货物 | sfx_grab_01，本地及可听范围接收 |
| CargoReleased | 每名参与者成功松手或关联被清理 | sfx_release_01，按清理原因控制是否播放 |
| CargoSecured / CargoUnsecured | 固定关系实际改变 | sfx_secure_01 / sfx_unsecure_01 |
| ObjectImpact | SourceEntityId、SurfaceId、Intensity01、PositionM | 按表面和强度选择碰撞变体 |
| RollingStarted / RollingStopped | 圆桶持续滚动状态改变 | sfx_metal_roll_loop_01 启停 |
| CargoDelivered | 某实例首次加入交付集合 | ui_delivered_01，向全体确认交付 |
| RoundCompleted | 本轮首次达到 6 件 | ui_round_complete_01，每端一次 |
| RequestDenied | 操作失败，结果码经 CommandResolved 提供 | ui_denied_01，仅请求者 |
| RoundReset | 回合编号变化 | 清理旧回合持续音效并重建环境状态 |

发动机运行和滑移使用 VehicleSnapshot 中归一化的 EngineLoad01、SkidIntensity01 持续参数。它们是声音驱动参数，B 在物理标定时发布映射规则。

EventId 结合回合编号在各接收端去重。木、金属、重金属碰撞的归一化强度初稿使用相对接触速度，低于 0.2 m/s 时不产生碰撞声音，0.2 至 4 m/s 映射到 0 至 1。持续接触的同对象音效节流规则引用 C 制作单。

## 9. 会话接入

~~~csharp
void Connect(SessionOptions options);
void Disconnect();
bool IsPhysicsAuthority { get; }
ulong LocalPlayerId { get; }
event Action<ulong> PlayerJoined;
event Action<ulong> PlayerLeft;
~~~

SessionOptions 定义连接角色、连接地址和会话配置 ID，具体传输由 B 的技术基线确定。D 提供最小双进程连接与玩家映射，E 将物体状态和回合状态接入同一配置。

输入发往当前物理裁决端，离散命令、状态快照和事件分开表达。多个玩家的输入都进入相应对象的更新，网络写入归属不占用其参与资格。

过期连续输入初始超时为 0.3 s。抓取目标超时后释放该玩家，驾驶输入超时后执行安全制动。重连恢复策略、快照频率和插值窗口由 B 的网络标定批次发布并覆盖到对应测试。

## 10. 接入顺序和必须通过的联调

| 批次 | D 提供 | E 提供 | B 接收的结果 |
|---|---|---|---|
| I01 | 公共契约接入、人物和手册、单人交互入口、双进程基础 | 车辆与货物实例、读取物理属性、力贡献接入点、场地出生点 | API 能编译映射，人物可在实际场地操作真实对象 |
| I02 | 两人参与列表、目标和松手、HUD、条件镜头 | 同物体合力合矩、座位、固定释放、载荷反馈 | 同向、反向、不同抓点和退出的共同作用测试 |
| I03 | 输入投递、生命周期清理、手册与视角回归 | 交付与重置、场景预置、状态传播和声音驱动参数 | 双人完整送货及重置，离散状态和计数一致 |

每次批次都同步策划反馈、文档版本、可运行增量、CI 结果和技术审查。B 记录问题及下一版修订，相关成员按同一版本更新。

## 11. 已知技术待定项

车辆控制、固定表示、具体 C# 工程结构、网络传输和测试框架由 B 的技术基线批次确定。本文已定义跨功能可观察语义，采用方案必须满足对应规则。B 统一发布适配和签名变更，实际运行和验收记录由实现后提供。
