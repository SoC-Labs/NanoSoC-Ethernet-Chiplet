// -----------------------------------------------------------------------------
// FIXTURE -- not a build product. See ci/fixtures/dft-scan/README.md.
//
// Real ordinary cell instantiations from the rc5vt-20260829 post-synthesis
// netlist, verbatim, with EVERY clock gate removed. Over 100 kB, parses, greps,
// and looks exactly like a gate netlist.
//
// MUTATION APPLIED HERE: every cg_*/CKLN* instance deleted. The census must
// call this UNVERIFIED, not clean: "0 clock gates tied low" out of 0 clock
// gates is a measurement of nothing.
// -----------------------------------------------------------------------------
module nanosoc_eth_chiplet_pads(VDD, VSS);
  input VDD, VSS;
  INVD2 g6161(.I (RxStartFrm), .ZN (n_259));
  INVD1 g6159(.I (RxStatusWriteLatched_sync2), .ZN (n_258));
  OAI31D2 g6516__2398(.A1 (n_224), .A2 (n_257), .A3 (n_265), .B
       (n_284), .ZN (n_350));
  DFSNQD1 PauseTimerEq0_sync2_reg(.SDN (n_21), .CP (MTxClk), .D
       (PauseTimerEq0_sync1), .Q (PauseTimerEq0_sync2));
  IND2D1 g6518__5107(.A1 (n_344), .B1 (SlotTimer[5]), .ZN (n_257));
  DFSNQD1 PauseTimerEq0_sync1_reg(.SDN (n_21), .CP (MTxClk), .D
       (n_256), .Q (PauseTimerEq0_sync1));
  CKND2D1 g6520__6260(.A1 (n_267), .A2 (RxFlow), .ZN (n_344));
  CKND1 g6521(.I (n_256), .ZN (n_267));
  NR2XD0 g6522__4319(.A1 (n_268), .A2 (PauseTimer[15]), .ZN (n_256));
  OR2D1 g6523__8428(.A1 (n_269), .A2 (PauseTimer[14]), .Z (n_268));
  OR2D1 g6524__5526(.A1 (n_270), .A2 (PauseTimer[13]), .Z (n_269));
  OR2XD1 g6525__6783(.A1 (n_271), .A2 (PauseTimer[12]), .Z (n_270));
  OR2XD1 g6526__3680(.A1 (n_272), .A2 (PauseTimer[11]), .Z (n_271));
  OR2XD1 g6527__1617(.A1 (n_273), .A2 (PauseTimer[10]), .Z (n_272));
  OR2XD1 g6528__2802(.A1 (n_274), .A2 (PauseTimer[9]), .Z (n_273));
  OR2XD1 g6529__1705(.A1 (n_275), .A2 (PauseTimer[8]), .Z (n_274));
  OAI21D1 g6546__5122(.A1 (n_282), .A2 (n_213), .B (n_259), .ZN
       (n_293));
  AO31D1 g6547__8246(.A1 (n_357), .A2 (n_196), .A3 (n_230), .B
       (RxEndFrm), .Z (n_290));
  OR2XD1 g6548__7098(.A1 (n_276), .A2 (PauseTimer[7]), .Z (n_275));
  AN2XD1 g6549__6131(.A1 (n_239), .A2 (AssembledTimerValue[7]), .Z
       (n_255));
  AN2XD1 g6550__1881(.A1 (n_239), .A2 (AssembledTimerValue[0]), .Z
       (n_254));
  AN2XD1 g6551__5115(.A1 (n_239), .A2 (AssembledTimerValue[1]), .Z
       (n_253));
  AN2XD1 g6552__7482(.A1 (n_239), .A2 (AssembledTimerValue[2]), .Z
       (n_252));
  AN2XD1 g6554__4733(.A1 (n_239), .A2 (AssembledTimerValue[3]), .Z
       (n_251));
  AN2XD1 g6555__6161(.A1 (n_239), .A2 (AssembledTimerValue[4]), .Z
       (n_250));
  AN2XD1 g6556__9315(.A1 (n_239), .A2 (AssembledTimerValue[5]), .Z
       (n_249));
  AN2XD1 g6557__9945(.A1 (n_239), .A2 (AssembledTimerValue[6]), .Z
       (n_248));
  AN2XD1 g6558__2883(.A1 (n_239), .A2 (AssembledTimerValue[10]), .Z
       (n_247));
  AN2XD1 g6559__2346(.A1 (n_239), .A2 (AssembledTimerValue[9]), .Z
       (n_246));
  AN2XD1 g6560__1666(.A1 (n_239), .A2 (AssembledTimerValue[12]), .Z
       (n_245));
  AN2XD1 g6561__7410(.A1 (n_239), .A2 (AssembledTimerValue[13]), .Z
       (n_244));
  AN2XD1 g6562__6417(.A1 (n_239), .A2 (AssembledTimerValue[14]), .Z
       (n_243));
  AN2XD1 g6563__5477(.A1 (n_239), .A2 (AssembledTimerValue[11]), .Z
       (n_242));
  AN2XD1 g6564__2398(.A1 (n_239), .A2 (AssembledTimerValue[15]), .Z
       (n_241));
  AN2XD1 g6565__5107(.A1 (n_239), .A2 (AssembledTimerValue[8]), .Z
       (n_240));
  OR2XD1 g6566__6260(.A1 (n_277), .A2 (PauseTimer[6]), .Z (n_276));
  OR2XD1 g6568__4319(.A1 (n_278), .A2 (PauseTimer[5]), .Z (n_277));
  CKAN2D4 g6569__8428(.A1 (n_238), .A2 (ReceivedPauseFrmWAddr), .Z
       (n_239));
  ND2D1 g6570__5526(.A1 (n_237), .A2 (n_259), .ZN (n_292));
  OR2D1 g6571__6783(.A1 (n_236), .A2 (ByteCnt[0]), .Z (n_282));
  CKND1 g6572(.I (n_238), .ZN (n_357));
  IND2D1 g6573__3680(.A1 (n_263), .B1 (ByteCnt[4]), .ZN (n_237));
  OR2XD1 g6574__1617(.A1 (n_279), .A2 (PauseTimer[4]), .Z (n_278));
  INR2XD0 g6575__2802(.A1 (ByteCnt[4]), .B1 (n_262), .ZN (n_238));
  IND3D1 g6576__1705(.A1 (n_283), .B1 (ByteCnt[4]), .B2 (RxValid), .ZN
       (n_236));
  IND2D1 g6577__5122(.A1 (n_266), .B1 (SlotTimer[4]), .ZN (n_265));
  ND4D8 g6578__8246(.A1 (n_233), .A2 (RxFlow), .A3
       (ReceivedPauseFrmWAddr), .A4 (ReceiveEnd), .ZN (n_284));
  OR2D1 g6579__7098(.A1 (n_286), .A2 (n_285), .Z (n_262));
  OR2XD1 g6580__6131(.A1 (n_280), .A2 (PauseTimer[3]), .Z (n_279));
  OAI21D1 g6581__1881(.A1 (n_224), .A2 (n_215), .B (n_21), .ZN (n_291));
  OR2D1 g6582__5115(.A1 (n_264), .A2 (n_283), .Z (n_263));
  IND2D1 g6583__7482(.A1 (n_288), .B1 (SlotTimer[3]), .ZN (n_266));
  IND2D1 g6600__4733(.A1 (n_289), .B1 (SlotTimer[2]), .ZN (n_288));
  OR2D1 g6601__6161(.A1 (n_287), .A2 (ByteCnt[0]), .Z (n_286));
  CKND2D1 g6602__9315(.A1 (n_235), .A2 (ByteCnt[1]), .ZN (n_285));
  ND2D1 g6603__9945(.A1 (n_196), .A2 (ByteCnt[0]), .ZN (n_264));
  OR2XD1 g6604__2883(.A1 (n_281), .A2 (PauseTimer[2]), .Z (n_280));
  IND2D1 g6605__2346(.A1 (ByteCnt[1]), .B1 (n_235), .ZN (n_283));
  AN2XD1 g6607__1666(.A1 (ReceivedLengthOK), .A2 (ReceivedPacketGood),
       .Z (n_233));
  IND2D1 g6610__7410(.A1 (DlyCrcCnt[2]), .B1 (DlyCrcEn), .ZN (n_230));
  NR2XD0 g6616__6417(.A1 (ByteCnt[2]), .A2 (ByteCnt[3]), .ZN (n_235));
  CKND2D1 g6626__5477(.A1 (SlotTimer[1]), .A2 (SlotTimer[0]), .ZN
       (n_289));
  OR2XD1 g6627__2398(.A1 (PauseTimer[1]), .A2 (PauseTimer[0]), .Z
       (n_281));
  CKND2D1 g6628__5107(.A1 (Pause), .A2 (Divider2), .ZN (n_224));
  CKND1 g6630(.I (RxFlow), .ZN (n_215));
  CKND1 g6631(.I (RxReset), .ZN (n_21));
  CKND1 g6632(.I (DetectionWindow), .ZN (n_213));
  CKND1 drc_bufs6666(.I (n_196), .ZN (n_287));
  AN2XD1 g2__6260(.A1 (RxValid), .A2 (DetectionWindow), .Z (n_196));
  OR2D1 g6684__4319(.A1 (ReceiveEnd), .A2 (n_239), .Z (n_356));
  DFCNQD1 AddressOK_reg(.CDN (n_21), .CP (MRxClk), .D (n_195), .Q
       (AddressOK));
  SDFSNQD1 DetectionWindow_reg(.SDN (n_21), .CP (MRxClk), .D
       (DetectionWindow), .SI (n_357), .SE (n_0), .Q (DetectionWindow));
  DFCNQD1 Divider2_reg(.CDN (n_21), .CP (MRxClk), .D (n_34), .Q
       (Divider2));
  DFCNQD1 OpCodeOK_reg(.CDN (n_21), .CP (MRxClk), .D (n_192), .Q
       (OpCodeOK));
  SDFCNQD1 Pause_reg(.CDN (n_21), .CP (MTxClk), .D (Pause), .SI (n_35),
       .SE (n_131), .Q (Pause));
  DFCNQD1 ReceivedPauseFrmWAddr_reg(.CDN (n_21), .CP (MRxClk), .D
       (n_168), .Q (ReceivedPauseFrmWAddr));
  SDFCNQD1 ReceivedPauseFrm_reg(.CDN (n_21), .CP (MRxClk), .D
       (ReceivedPauseFrm), .SI (n_86), .SE (n_130), .Q
       (ReceivedPauseFrm));
  SDFCNQD1 TypeLengthOK_reg(.CDN (n_21), .CP (MRxClk), .D (n_1), .SI
       (TypeLengthOK), .SE (n_156), .Q (TypeLengthOK));
  MOAI22D1 g9153__8428(.A1 (n_194), .A2 (n_185), .B1 (n_185), .B2
       (AddressOK), .ZN (n_195));
  AOI21D1 g9154__5526(.A1 (n_186), .A2 (AddressOK), .B (n_193), .ZN
       (n_194));
  MOAI22D1 g9156__6783(.A1 (n_190), .A2 (ByteCnt[3]), .B1 (n_5), .B2
       (n_112), .ZN (n_193));
  INR2XD0 g9158__3680(.A1 (n_282), .B1 (n_188), .ZN (n_192));
  NR2XD0 g9159__1617(.A1 (n_189), .A2 (RxEndFrm), .ZN (n_191));
  ND3D1 g9162__2802(.A1 (n_182), .A2 (n_110), .A3 (AddressOK), .ZN
       (n_190));
  MAOI22D1 g9163__1705(.A1 (n_179), .A2 (ByteCnt[4]), .B1 (n_179), .B2
       (ByteCnt[4]), .ZN (n_189));
  MAOI22D1 g9164__5122(.A1 (n_155), .A2 (OpCodeOK), .B1 (n_183), .B2
       (n_155), .ZN (n_188));
  OA211D1 g9165__8246(.A1 (ByteCnt[3]), .A2 (n_154), .B (n_179), .C
       (n_27), .Z (n_187));
  OAI211D1 g9166__7098(.A1 (n_114), .A2 (n_177), .B (n_180), .C
       (n_178), .ZN (n_186));
  OAI31D1 g9167__6131(.A1 (n_88), .A2 (n_105), .A3 (n_174), .B (n_170),
       .ZN (n_184));
  NR4D1 g9168__1881(.A1 (n_169), .A2 (n_55), .A3 (n_54), .A4
       (ReceiveEnd), .ZN (n_185));
  AOI32D1 g9169__5115(.A1 (n_171), .A2 (OpCodeOK), .A3 (ByteCnt[0]),
       .B1 (n_165), .B2 (n_26), .ZN (n_183));
  OAI22D1 g9170__7482(.A1 (n_167), .A2 (n_286), .B1 (n_176), .B2
       (n_264), .ZN (n_182));
  INR3D0 g9172__4733(.A1 (ByteCnt[3]), .B1 (n_31), .B2 (n_166), .ZN
       (n_181));
  AOI33D1 g9173__6161(.A1 (n_160), .A2 (n_6), .A3 (n_55), .B1 (n_163),
       .B2 (n_140), .B3 (n_13), .ZN (n_180));
  CKND2D1 g9177__9315(.A1 (n_154), .A2 (ByteCnt[3]), .ZN (n_179));
  IND4D1 g9178__9945(.A1 (n_147), .B1 (n_157), .B2 (n_54), .B3 (n_119),
       .ZN (n_178));
  AOI31D1 g9179__2883(.A1 (n_162), .A2 (n_149), .A3 (n_121), .B
       (n_165), .ZN (n_177));
  AOI31D1 g9180__2346(.A1 (n_3), .A2 (n_144), .A3 (n_122), .B (n_171),
       .ZN (n_176));
  AOI211XD0 g9181__1666(.A1 (n_41), .A2 (n_28), .B (n_154), .C
       (RxEndFrm), .ZN (n_175));
  OAI211D1 g9182__7410(.A1 (MAC[45]), .A2 (n_33), .B (n_4), .C (n_74),
       .ZN (n_174));
  AN2XD1 g9183__6417(.A1 (n_164), .A2 (n_42), .Z (n_173));
  AOI21D1 g9184__5477(.A1 (n_148), .A2 (n_106), .B (n_43), .ZN (n_172));
  CKND1 g9187(.I (n_170), .ZN (n_171));
  OAI211D1 g9188__2398(.A1 (ByteCnt[3]), .A2 (n_141), .B (n_113), .C
       (n_114), .ZN (n_169));
  MOAI22D1 g9189__5107(.A1 (n_152), .A2 (ReceiveEnd), .B1 (n_152), .B2
       (ReceivedPauseFrmWAddr), .ZN (n_168));
  AOI31D1 g9190__6260(.A1 (n_146), .A2 (n_128), .A3 (n_117), .B
       (n_165), .ZN (n_167));
  ND4D1 g9191__4319(.A1 (n_125), .A2 (n_109), .A3 (n_110), .A4 (n_115),
       .ZN (n_166));
  IND3D1 g9192__8428(.A1 (n_151), .B1 (n_22), .B2 (n_11), .ZN (n_170));
  MOAI22D1 g9206__5526(.A1 (n_40), .A2 (n_44), .B1 (n_40), .B2
       (DlyCrcCnt[2]), .ZN (n_164));
  MOAI22D1 g9207__6783(.A1 (n_127), .A2 (n_11), .B1 (n_54), .B2
       (n_109), .ZN (n_163));
  OA211D1 g9208__3680(.A1 (MAC[17]), .A2 (n_16), .B (n_381), .C
       (n_120), .Z (n_162));
  AOI211XD0 g9209__1617(.A1 (n_33), .A2 (MAC[5]), .B (n_116), .C
       (n_123), .ZN (n_161));
  AOI211XD0 g9210__2802(.A1 (n_33), .A2 (MAC[29]), .B (n_145), .C
       (n_85), .ZN (n_160));
  AOI211XD0 g9211__1705(.A1 (n_16), .A2 (MAC[25]), .B (n_124), .C
       (n_134), .ZN (n_159));
  AOI211XD0 g9212__5122(.A1 (n_33), .A2 (MAC[45]), .B (n_138), .C
       (n_118), .ZN (n_158));
  AOI211XD0 g9213__8246(.A1 (n_22), .A2 (MAC[39]), .B (n_143), .C
       (n_79), .ZN (n_157));
  AOI21D1 g9215__7098(.A1 (n_142), .A2 (ByteCnt[3]), .B (ReceiveEnd),
       .ZN (n_156));
  AN3XD1 g9219__6131(.A1 (n_140), .A2 (n_109), .A3 (n_22), .Z (n_165));
  NR2XD0 g9220__1881(.A1 (n_129), .A2 (n_43), .ZN (n_153));
  OR2D1 g9222__5115(.A1 (n_132), .A2 (ByteCnt[4]), .Z (n_155));
  NR2XD1 g9225__7482(.A1 (n_41), .A2 (n_28), .ZN (n_154));
  CKND2D1 g9229__4733(.A1 (n_140), .A2 (n_45), .ZN (n_151));
  OA211D1 g9230__6161(.A1 (ByteCnt[1]), .A2 (ByteCnt[0]), .B (n_41), .C
       (n_27), .Z (n_150));
  OA211D1 g9231__9315(.A1 (MAC[21]), .A2 (n_33), .B (n_65), .C (n_58),
       .Z (n_149));
  OAI211D1 g9232__9945(.A1 (DlyCrcCnt[1]), .A2 (DlyCrcCnt[0]), .B
       (n_44), .C (n_39), .ZN (n_148));
  OAI211D1 g9233__2883(.A1 (MAC[32]), .A2 (n_23), .B (n_63), .C (n_77),
       .ZN (n_147));
  AN4XD1 g9234__2346(.A1 (n_66), .A2 (n_60), .A3 (n_73), .A4 (n_61), .Z
       (n_146));
  AO211D1 g9235__1666(.A1 (n_14), .A2 (MAC[28]), .B (n_70), .C (n_75),
       .Z (n_145));
  AOI211XD0 g9236__7410(.A1 (n_23), .A2 (MAC[0]), .B (n_67), .C (n_62),
       .ZN (n_144));
  AO211D1 g9237__6417(.A1 (n_14), .A2 (MAC[36]), .B (n_64), .C (n_57),
       .Z (n_143));
  AOI21D1 g9238__5477(.A1 (n_20), .A2 (AddressOK), .B (ReceiveEnd), .ZN
       (n_152));
  CKND1 g9239(.I (n_141), .ZN (n_142));
  NR2XD0 g9240__2398(.A1 (n_94), .A2 (RxReset), .ZN (n_139));
  OAI211D1 g9241__5107(.A1 (MAC[43]), .A2 (n_31), .B (n_69), .C (n_48),
       .ZN (n_138));
  NR2XD0 g9242__6260(.A1 (n_56), .A2 (RxReset), .ZN (n_137));
  NR2XD0 g9243__4319(.A1 (n_87), .A2 (RxReset), .ZN (n_136));
  NR2XD0 g9244__8428(.A1 (n_89), .A2 (RxReset), .ZN (n_135));
  OAI211D1 g9245__5526(.A1 (MAC[27]), .A2 (n_31), .B (n_72), .C (n_50),
       .ZN (n_134));
  NR2XD0 g9246__6783(.A1 (n_107), .A2 (RxReset), .ZN (n_133));
  IND4D1 g9247__3680(.A1 (n_287), .B1 (ByteCnt[1]), .B2 (ByteCnt[2]),
       .B3 (ByteCnt[3]), .ZN (n_132));
  AOI21D1 g9248__1617(.A1 (n_52), .A2 (TxUsedDataOutDetected), .B
       (TxStartFrmOut), .ZN (n_131));
  ND2D1 g9249__2802(.A1 (n_111), .A2 (n_86), .ZN (n_130));
  IND2D1 g9250__1705(.A1 (n_287), .B1 (n_110), .ZN (n_141));
  AN2XD1 g9251__5122(.A1 (n_115), .A2 (n_31), .Z (n_140));
  MAOI22D1 g9253__8246(.A1 (n_40), .A2 (DlyCrcCnt[0]), .B1 (n_40), .B2
       (DlyCrcCnt[0]), .ZN (n_129));
  AOI211XD0 g9254__7098(.A1 (n_31), .A2 (MAC[11]), .B (n_59), .C
       (n_37), .ZN (n_128));
  ND3D1 g9255__6131(.A1 (n_55), .A2 (n_19), .A3 (n_17), .ZN (n_127));
  AOI211XD0 g9256__1881(.A1 (n_16), .A2 (MAC[17]), .B (n_71), .C
       (n_38), .ZN (n_126));
  OAI22D1 g9257__5115(.A1 (n_47), .A2 (n_13), .B1 (n_286), .B2 (n_22),
       .ZN (n_125));
  OAI221D1 g9258__7482(.A1 (n_16), .A2 (MAC[25]), .B1 (MAC[26]), .B2
       (n_24), .C (n_53), .ZN (n_124));
  OAI221D1 g9259__4733(.A1 (n_22), .A2 (MAC[7]), .B1 (MAC[5]), .B2
       (n_33), .C (n_46), .ZN (n_123));
  AOI21D1 g9260__6161(.A1 (n_16), .A2 (MAC[1]), .B (n_83), .ZN (n_122));
  OA21D1 g9261__9315(.A1 (n_22), .A2 (MAC[23]), .B (n_82), .Z (n_121));
  OA21D1 g9262__9945(.A1 (n_24), .A2 (MAC[18]), .B (n_80), .Z (n_120));
  OA21D1 g9263__2883(.A1 (n_31), .A2 (MAC[35]), .B (n_78), .Z (n_119));
  OAI221D1 g9264__2346(.A1 (n_23), .A2 (MAC[40]), .B1 (MAC[42]), .B2
       (n_24), .C (n_84), .ZN (n_118));
  OA221D0 g9265__1666(.A1 (n_23), .A2 (MAC[8]), .B1 (MAC[9]), .B2
       (n_16), .C (n_81), .Z (n_117));
  OAI211D1 g9266__7410(.A1 (MAC[4]), .A2 (n_14), .B (n_68), .C (n_49),
       .ZN (n_116));
  CKND1 g9267(.I (n_112), .ZN (n_113));
  IOA21D1 g9269__6417(.A1 (n_281), .A2 (PauseTimer[2]), .B (n_280), .ZN
       (n_108));
  MAOI22D1 g9270__5477(.A1 (n_265), .A2 (SlotTimer[5]), .B1 (n_265),
       .B2 (SlotTimer[5]), .ZN (n_107));
  CKND2D1 g9271__2398(.A1 (n_40), .A2 (DlyCrcCnt[1]), .ZN (n_106));
  MAOI22D1 g9272__5107(.A1 (n_19), .A2 (MAC[46]), .B1 (n_19), .B2
       (MAC[46]), .ZN (n_105));
  IOA21D1 g9273__6260(.A1 (n_274), .A2 (PauseTimer[9]), .B (n_273), .ZN
       (n_104));
  IOA21D1 g9274__4319(.A1 (n_273), .A2 (PauseTimer[10]), .B (n_272),
       .ZN (n_103));
  IOA21D1 g9275__8428(.A1 (n_272), .A2 (PauseTimer[11]), .B (n_271),
       .ZN (n_102));
  IOA21D1 g9276__5526(.A1 (n_271), .A2 (PauseTimer[12]), .B (n_270),
       .ZN (n_101));
  IOA21D1 g9277__6783(.A1 (n_270), .A2 (PauseTimer[13]), .B (n_269),
       .ZN (n_100));
  IOA21D1 g9278__3680(.A1 (n_269), .A2 (PauseTimer[14]), .B (n_268),
       .ZN (n_99));
  IOA21D1 g9279__1617(.A1 (n_268), .A2 (PauseTimer[15]), .B (n_267),
       .ZN (n_98));
  IOA21D1 g9280__2802(.A1 (n_276), .A2 (PauseTimer[7]), .B (n_275), .ZN
       (n_97));
  IOA21D1 g9281__1705(.A1 (n_275), .A2 (PauseTimer[8]), .B (n_274), .ZN
       (n_96));
  IOA21D1 g9282__5122(.A1 (PauseTimer[1]), .A2 (PauseTimer[0]), .B
       (n_281), .ZN (n_95));
  MAOI22D1 g9283__8246(.A1 (n_266), .A2 (SlotTimer[4]), .B1 (n_266),
       .B2 (SlotTimer[4]), .ZN (n_94));
  IOA21D1 g9284__7098(.A1 (n_280), .A2 (PauseTimer[3]), .B (n_279), .ZN
       (n_93));
  IOA21D1 g9285__6131(.A1 (n_279), .A2 (PauseTimer[4]), .B (n_278), .ZN
       (n_92));
  IOA21D1 g9286__1881(.A1 (n_278), .A2 (PauseTimer[5]), .B (n_277), .ZN
       (n_91));
  IOA21D1 g9287__5115(.A1 (n_277), .A2 (PauseTimer[6]), .B (n_276), .ZN
       (n_90));
  MAOI22D1 g9288__7482(.A1 (n_288), .A2 (SlotTimer[3]), .B1 (n_288),
       .B2 (SlotTimer[3]), .ZN (n_89));
  MAOI22D1 g9289__4733(.A1 (n_15), .A2 (MAC[44]), .B1 (n_15), .B2
       (MAC[44]), .ZN (n_88));
  MAOI22D1 g9290__6161(.A1 (SlotTimer[2]), .A2 (n_289), .B1
       (SlotTimer[2]), .B2 (n_289), .ZN (n_87));
  AN3XD1 g9292__9315(.A1 (n_24), .A2 (n_14), .A3 (n_33), .Z (n_115));
  OR3XD1 g9293__9945(.A1 (ByteCnt[4]), .A2 (n_285), .A3 (n_264), .Z
       (n_114));
  NR3D1 g9294__2883(.A1 (n_286), .A2 (n_283), .A3 (ByteCnt[4]), .ZN
       (n_112));
  IND3D1 g9295__2346(.A1 (n_282), .B1 (TypeLengthOK), .B2 (OpCodeOK),
       .ZN (n_111));
  NR3D1 g9296__1666(.A1 (n_28), .A2 (ByteCnt[1]), .A3 (ByteCnt[4]), .ZN
       (n_110));
  AN2XD1 g9297__7410(.A1 (n_45), .A2 (n_23), .Z (n_109));
  OAI22D1 g9300__6417(.A1 (n_14), .A2 (MAC[28]), .B1 (n_33), .B2
       (MAC[29]), .ZN (n_85));
  AOI22D1 g9301__5477(.A1 (n_23), .A2 (MAC[40]), .B1 (n_24), .B2
       (MAC[42]), .ZN (n_84));
  OAI22D1 g9302__2398(.A1 (n_23), .A2 (MAC[0]), .B1 (n_16), .B2
       (MAC[1]), .ZN (n_83));
  AOI22D1 g9303__5107(.A1 (n_33), .A2 (MAC[21]), .B1 (n_22), .B2
       (MAC[23]), .ZN (n_82));
  AOI22D1 g9304__6260(.A1 (n_23), .A2 (MAC[8]), .B1 (n_16), .B2
       (MAC[9]), .ZN (n_81));
  AOI22D1 g9305__4319(.A1 (n_24), .A2 (MAC[18]), .B1 (n_31), .B2
       (MAC[19]), .ZN (n_80));
  OAI22D1 g9306__8428(.A1 (n_14), .A2 (MAC[36]), .B1 (n_22), .B2
       (MAC[39]), .ZN (n_79));
  AOI22D1 g9307__5526(.A1 (n_23), .A2 (MAC[32]), .B1 (n_24), .B2
       (MAC[34]), .ZN (n_78));
  MAOI22D1 g9308__6783(.A1 (n_31), .A2 (MAC[35]), .B1 (n_24), .B2
       (MAC[34]), .ZN (n_77));
  MOAI22D1 g9309__3680(.A1 (SetPauseTimer), .A2 (PauseTimer[0]), .B1
       (SetPauseTimer), .B2 (LatchedTimerValue[0]), .ZN (n_76));
  MOAI22D1 g9310__1617(.A1 (n_22), .A2 (MAC[31]), .B1 (n_22), .B2
       (MAC[31]), .ZN (n_75));
  MAOI22D1 g9311__2802(.A1 (n_22), .A2 (MAC[47]), .B1 (n_22), .B2
       (MAC[47]), .ZN (n_74));
  MAOI22D1 g9312__1705(.A1 (n_22), .A2 (MAC[15]), .B1 (n_22), .B2
       (MAC[15]), .ZN (n_73));
  MAOI22D1 g9313__5122(.A1 (n_23), .A2 (MAC[24]), .B1 (n_23), .B2
       (MAC[24]), .ZN (n_72));
  MOAI22D1 g9314__8246(.A1 (n_23), .A2 (MAC[16]), .B1 (n_23), .B2
       (MAC[16]), .ZN (n_71));
  MUX2ND0 g9315__7098(.I0 (n_32), .I1 (n_19), .S (MAC[30]), .ZN (n_70));
  MAOI22D1 g9316__6131(.A1 (n_16), .A2 (MAC[41]), .B1 (n_16), .B2
       (MAC[41]), .ZN (n_69));
  MUX2ND1 g9317__1881(.I0 (n_19), .I1 (n_32), .S (MAC[6]), .ZN (n_68));
  MOAI22D1 g9318__5115(.A1 (n_31), .A2 (MAC[3]), .B1 (n_31), .B2
       (MAC[3]), .ZN (n_67));
  MUX2ND0 g9319__7482(.I0 (n_19), .I1 (n_32), .S (MAC[14]), .ZN (n_66));
  MUX2ND0 g9320__4733(.I0 (n_19), .I1 (n_32), .S (MAC[22]), .ZN (n_65));
  MUX2ND0 g9321__6161(.I0 (n_32), .I1 (n_19), .S (MAC[38]), .ZN (n_64));
  MAOI22D1 g9322__9315(.A1 (n_16), .A2 (MAC[33]), .B1 (n_16), .B2
       (MAC[33]), .ZN (n_63));
  MOAI22D1 g9323__9945(.A1 (n_24), .A2 (MAC[2]), .B1 (n_24), .B2
       (MAC[2]), .ZN (n_62));
  MAOI22D1 g9324__2883(.A1 (n_33), .A2 (MAC[13]), .B1 (n_33), .B2
       (MAC[13]), .ZN (n_61));
  MAOI22D1 g9325__2346(.A1 (n_14), .A2 (MAC[12]), .B1 (n_14), .B2
       (MAC[12]), .ZN (n_60));
  MOAI22D1 g9326__1666(.A1 (n_24), .A2 (MAC[10]), .B1 (n_24), .B2
       (MAC[10]), .ZN (n_59));
  MAOI22D1 g9327__7410(.A1 (n_14), .A2 (MAC[20]), .B1 (n_14), .B2
       (MAC[20]), .ZN (n_58));
  MOAI22D1 g9328__6417(.A1 (n_33), .A2 (MAC[37]), .B1 (n_33), .B2
       (MAC[37]), .ZN (n_57));
  XNR2D1 g9329__5477(.A1 (SlotTimer[0]), .A2 (SlotTimer[1]), .ZN
       (n_56));
  MOAI22D1 g9330__2398(.A1 (ReceivedPauseFrm), .A2 (r_PassAll), .B1
       (n_258), .B2 (r_PassAll), .ZN (n_86));
  ND2D1 g9331__5107(.A1 (n_24), .A2 (MAC[26]), .ZN (n_53));
  NR2D1 g9332__6260(.A1 (TxAbortIn), .A2 (TxDoneIn), .ZN (n_52));
  NR2XD0 g9333__4319(.A1 (RxReset), .A2 (SlotTimer[0]), .ZN (n_51));
  ND2D1 g9334__8428(.A1 (n_31), .A2 (MAC[27]), .ZN (n_50));
  ND2D1 g9335__5526(.A1 (n_14), .A2 (MAC[4]), .ZN (n_49));
  ND2D1 g9336__6783(.A1 (n_31), .A2 (MAC[43]), .ZN (n_48));
  IND2D1 g9337__3680(.A1 (n_264), .B1 (TypeLengthOK), .ZN (n_47));
  ND2D1 g9338__1617(.A1 (n_22), .A2 (MAC[7]), .ZN (n_46));
  NR2XD1 g9339__2802(.A1 (n_262), .A2 (ByteCnt[4]), .ZN (n_55));
  NR2XD1 g9340__1705(.A1 (n_263), .A2 (ByteCnt[4]), .ZN (n_54));
  CKND1 g9341(.I (n_42), .ZN (n_43));
  CKND1 g9342(.I (n_39), .ZN (n_40));
  NR2D1 g9343__5122(.A1 (n_31), .A2 (MAC[19]), .ZN (n_38));
  NR2D1 g9344__8246(.A1 (n_31), .A2 (MAC[11]), .ZN (n_37));
  NR2XD0 g9345__7098(.A1 (ByteCnt[0]), .A2 (RxEndFrm), .ZN (n_36));
  INR2XD0 g9346__6131(.A1 (RxFlow), .B1 (PauseTimerEq0_sync2), .ZN
       (n_35));
  NR2XD0 g9347__1881(.A1 (n_344), .A2 (Divider2), .ZN (n_34));
  NR2XD0 g9349__5115(.A1 (n_17), .A2 (n_19), .ZN (n_45));
  ND2D1 g9350__7482(.A1 (DlyCrcCnt[0]), .A2 (DlyCrcCnt[1]), .ZN (n_44));
  ND2D1 g9351__4733(.A1 (RxEndFrm), .A2 (RxValid), .ZN (n_42));
  CKND2D1 g9352__6161(.A1 (ByteCnt[1]), .A2 (ByteCnt[0]), .ZN (n_41));
  INR2XD0 g9353__9315(.A1 (RxValid), .B1 (DlyCrcCnt[2]), .ZN (n_39));
  INVD3 g9358(.I (RxData[5]), .ZN (n_33));
  CKND1 g9359(.I (n_19), .ZN (n_32));
  INVD3 g9360(.I (RxData[3]), .ZN (n_31));
  CKND1 g9362(.I (n_284), .ZN (SetPauseTimer));
  CKND1 g9372(.I (RxEndFrm), .ZN (n_27));
  INVD3 g9378(.I (RxData[2]), .ZN (n_24));
  INVD3 g9379(.I (n_11), .ZN (n_23));
  INVD4 g9380(.I (n_13), .ZN (n_22));
  INVD2 drc_bufs6685(.I (n_18), .ZN (n_19));
  INVD1 drc_bufs9383(.I (RxData[6]), .ZN (n_18));
  CKND1 drc_bufs9387(.I (n_16), .ZN (n_17));
  INVD3 drc_bufs9388(.I (RxData[1]), .ZN (n_16));
  CKND1 drc_bufs9391(.I (n_14), .ZN (n_15));
  INVD2 drc_bufs9392(.I (RxData[4]), .ZN (n_14));
  CKND1 drc_bufs9395(.I (n_12), .ZN (n_13));
  INVD1 drc_bufs9396(.I (RxData[7]), .ZN (n_12));
  CKND1 drc_bufs9399(.I (n_10), .ZN (n_11));
  INVD1 drc_bufs9400(.I (RxData[0]), .ZN (n_10));
  BUFFD0 drc(.I (n_159), .Z (n_6));
  BUFFD0 drc9407(.I (n_184), .Z (n_5));
  BUFFD0 drc9414(.I (n_161), .Z (n_3));
  BUFFD0 drc9416(.I (n_175), .Z (n_2));
  BUFFD0 drc9418(.I (n_181), .Z (n_1));
  INVD1 drc_bufs9421(.I (n_111), .ZN (n_20));
  BUFFD0 drc9432(.I (n_158), .Z (n_4));
  IND2D1 g6686__9945(.A1 (ReceiveEnd), .B1 (n_357), .ZN (n_0));
  AN2XD1 g9442__2883(.A1 (n_259), .A2 (RxData[6]), .Z (n_370));
  AN2XD1 g9443__2346(.A1 (n_259), .A2 (RxData[2]), .Z (n_371));
  AN2XD1 g9444__1666(.A1 (n_259), .A2 (RxData[3]), .Z (n_372));
  AN2XD1 g9445__7410(.A1 (n_259), .A2 (RxData[4]), .Z (n_373));
  AN2XD1 g9446__6417(.A1 (n_259), .A2 (RxData[5]), .Z (n_374));
  AN2XD1 g9447__5477(.A1 (n_259), .A2 (RxData[1]), .Z (n_375));
  AN2XD1 g9448__2398(.A1 (n_259), .A2 (RxData[7]), .Z (n_376));
  AN2XD1 g9449__5107(.A1 (n_259), .A2 (RxData[0]), .Z (n_377));
  BUFFD0 drc9456(.I (n_126), .Z (n_381));
  INVD1 g2357(.I (TxUsedDataOutDetected), .ZN (n_132));
  DFQD1 ControlEnd_q_reg(.CP (MTxClk), .D (n_81), .Q (ControlEnd_q));
  DFQD1 TxCtrlStartFrm_q_reg(.CP (MTxClk), .D (TxCtrlStartFrm), .Q
       (TxCtrlStartFrm_q));
  DFCNQD1 TxUsedDataIn_q_reg(.CDN (n_1), .CP (MTxClk), .D
       (TxUsedDataIn), .Q (TxUsedDataIn_q));
  IND4D1 g3893__6260(.A1 (n_90), .B1 (n_120), .B2 (n_95), .B3 (n_94),
       .ZN (n_131));
  IND4D1 g3894__4319(.A1 (n_90), .B1 (n_121), .B2 (n_114), .B3 (n_113),
       .ZN (n_130));
  IND4D1 g3895__8428(.A1 (n_90), .B1 (n_104), .B2 (n_122), .B3 (n_87),
       .ZN (n_129));
  AO221D0 g3896__5526(.A1 (n_79), .A2 (MAC[24]), .B1 (n_80), .B2
       (MAC[40]), .C (n_126), .Z (n_128));
  ND3D1 g3897__6783(.A1 (n_118), .A2 (n_119), .A3 (n_106), .ZN (n_127));
  ND4D1 g3898__3680(.A1 (n_117), .A2 (n_88), .A3 (n_115), .A4 (n_86),
       .ZN (n_126));
  ND4D1 g3899__1617(.A1 (n_110), .A2 (n_108), .A3 (n_109), .A4 (n_107),
       .ZN (n_125));
  ND4D1 g3900__2802(.A1 (n_102), .A2 (n_101), .A3 (n_100), .A4 (n_91),
       .ZN (n_124));
  ND4D1 g3901__1705(.A1 (n_99), .A2 (n_97), .A3 (n_96), .A4 (n_98), .ZN
       (n_123));
  OAI21D1 g3902__5122(.A1 (n_105), .A2 (n_136), .B (n_2), .ZN (n_143));
  OA211D1 g3903__8246(.A1 (n_59), .A2 (n_70), .B (n_116), .C (n_89), .Z
       (n_122));
  AN2XD1 g3904__7098(.A1 (n_111), .A2 (n_112), .Z (n_121));
  AN2XD1 g3905__6131(.A1 (n_92), .A2 (n_93), .Z (n_120));
  AOI21D1 g3906__1881(.A1 (n_84), .A2 (MAC[11]), .B (n_103), .ZN
       (n_119));
  AOI22D1 g3907__5115(.A1 (n_81), .A2 (TxPauseTV[3]), .B1 (n_83), .B2
       (MAC[3]), .ZN (n_118));
  AOI32D1 g3908__7482(.A1 (n_67), .A2 (n_53), .A3 (ByteCnt[3]), .B1
       (n_78), .B2 (MAC[16]), .ZN (n_117));
  AOI22D1 g3909__4733(.A1 (n_77), .A2 (MAC[39]), .B1 (n_68), .B2
       (MAC[47]), .ZN (n_116));
  AOI22D1 g3910__6161(.A1 (n_82), .A2 (TxPauseTV[8]), .B1 (n_81), .B2
       (TxPauseTV[0]), .ZN (n_115));
  AOI22D1 g3911__9315(.A1 (n_83), .A2 (MAC[1]), .B1 (n_85), .B2
       (MAC[9]), .ZN (n_114));
  AOI22D1 g3912__9945(.A1 (n_82), .A2 (TxPauseTV[9]), .B1 (n_81), .B2
       (TxPauseTV[1]), .ZN (n_113));
  AOI22D1 g3913__2883(.A1 (n_78), .A2 (MAC[17]), .B1 (n_68), .B2
       (MAC[41]), .ZN (n_112));
  AOI22D1 g3914__2346(.A1 (n_79), .A2 (MAC[25]), .B1 (n_77), .B2
       (MAC[33]), .ZN (n_111));
  AOI22D1 g3915__1666(.A1 (n_84), .A2 (MAC[10]), .B1 (n_83), .B2
       (MAC[2]), .ZN (n_110));
  AOI22D1 g3916__7410(.A1 (n_79), .A2 (MAC[26]), .B1 (n_77), .B2
       (MAC[34]), .ZN (n_109));
  AOI22D1 g3917__6417(.A1 (n_80), .A2 (MAC[42]), .B1 (n_81), .B2
       (TxPauseTV[2]), .ZN (n_108));
  AOI22D1 g3918__5477(.A1 (n_82), .A2 (TxPauseTV[10]), .B1 (n_78), .B2
       (MAC[18]), .ZN (n_107));
  AOI22D1 g3919__2398(.A1 (n_80), .A2 (MAC[43]), .B1 (n_77), .B2
       (MAC[35]), .ZN (n_106));
  AOI21D1 g3920__5107(.A1 (n_139), .A2 (TxUsedDataIn), .B (n_61), .ZN
       (n_105));
  AOI22D1 g3921__6260(.A1 (n_83), .A2 (MAC[7]), .B1 (n_85), .B2
       (MAC[15]), .ZN (n_104));
  MOAI22D1 g3922__4319(.A1 (n_76), .A2 (n_64), .B1 (n_82), .B2
       (TxPauseTV[11]), .ZN (n_103));
  AOI22D1 g3923__8428(.A1 (n_84), .A2 (MAC[12]), .B1 (n_83), .B2
       (MAC[4]), .ZN (n_102));
  AOI22D1 g3924__5526(.A1 (n_80), .A2 (MAC[44]), .B1 (n_81), .B2
       (TxPauseTV[4]), .ZN (n_101));
  AOI22D1 g3925__6783(.A1 (n_79), .A2 (MAC[28]), .B1 (n_77), .B2
       (MAC[36]), .ZN (n_100));
  AOI22D1 g3926__3680(.A1 (n_84), .A2 (MAC[13]), .B1 (n_83), .B2
       (MAC[5]), .ZN (n_99));
  AOI22D1 g3927__1617(.A1 (n_82), .A2 (TxPauseTV[13]), .B1 (n_78), .B2
       (MAC[21]), .ZN (n_98));
  AOI22D1 g3928__2802(.A1 (n_80), .A2 (MAC[45]), .B1 (n_81), .B2
       (TxPauseTV[5]), .ZN (n_97));
  AOI22D1 g3929__1705(.A1 (n_79), .A2 (MAC[29]), .B1 (n_77), .B2
       (MAC[37]), .ZN (n_96));
  AOI22D1 g3930__5122(.A1 (n_83), .A2 (MAC[6]), .B1 (n_85), .B2
       (MAC[14]), .ZN (n_95));
  AOI22D1 g3931__8246(.A1 (n_82), .A2 (TxPauseTV[14]), .B1 (n_81), .B2
       (TxPauseTV[6]), .ZN (n_94));
  AOI22D1 g3932__7098(.A1 (n_78), .A2 (MAC[22]), .B1 (n_68), .B2
       (MAC[46]), .ZN (n_93));
  AOI22D1 g3933__6131(.A1 (n_79), .A2 (MAC[30]), .B1 (n_77), .B2
       (MAC[38]), .ZN (n_92));
  AOI22D1 g3934__1881(.A1 (n_82), .A2 (TxPauseTV[12]), .B1 (n_78), .B2
       (MAC[20]), .ZN (n_91));
  ND2D1 g3936__5115(.A1 (n_82), .A2 (TxPauseTV[15]), .ZN (n_89));
  AN2XD1 g3937__7482(.A1 (n_85), .A2 (n_48), .Z (n_90));
  ND2D1 g3938__4733(.A1 (n_84), .A2 (MAC[8]), .ZN (n_88));
  AOI31D1 g3939__6161(.A1 (n_60), .A2 (n_53), .A3 (TxPauseTV[7]), .B
       (n_46), .ZN (n_87));
  OA32D0 g3940__9315(.A1 (n_137), .A2 (n_52), .A3 (n_63), .B1 (n_72),
       .B2 (n_70), .Z (n_86));
  CKND1 g3941(.I (n_81), .ZN (n_139));
  AN2XD1 g3942__9945(.A1 (n_73), .A2 (n_4), .Z (n_85));
  AN2XD1 g3943__2883(.A1 (n_73), .A2 (n_54), .Z (n_84));
  AN2D2 g3944__2346(.A1 (n_73), .A2 (n_55), .Z (n_83));
  AN2D2 g3945__1666(.A1 (n_74), .A2 (n_56), .Z (n_82));
  AN2D2 g3946__7410(.A1 (n_74), .A2 (n_53), .Z (n_81));
  AOI21D1 g3947__6417(.A1 (n_55), .A2 (MAC[19]), .B (n_66), .ZN (n_76));
  NR3D0 g3948__5477(.A1 (n_64), .A2 (n_138), .A3 (n_57), .ZN (n_75));
  AN2XD1 g3949__2398(.A1 (n_68), .A2 (ByteCnt[3]), .Z (n_80));
  NR2D2 g3950__5107(.A1 (n_70), .A2 (n_138), .ZN (n_79));
  AN2XD1 g3951__6260(.A1 (n_69), .A2 (n_55), .Z (n_78));
  AN3D2 g3952__4319(.A1 (n_62), .A2 (n_53), .A3 (ByteCnt[3]), .Z
       (n_77));
  ND2D1 g3953__8428(.A1 (n_65), .A2 (n_56), .ZN (n_72));
  CKND2D1 g3954__5526(.A1 (n_65), .A2 (CtrlMux), .ZN (n_136));
  AN2XD1 g3955__6783(.A1 (n_60), .A2 (ByteCnt[5]), .Z (n_74));
  NR2D2 g3956__3680(.A1 (n_63), .A2 (ByteCnt[3]), .ZN (n_73));
  CKND1 g3957(.I (ResetByteCnt), .ZN (n_2));
  INVD2 g3958(.I (n_47), .ZN (n_70));
  IOA21D1 g3959__1617(.A1 (n_58), .A2 (MAC[32]), .B (n_64), .ZN (n_67));
  AO22D0 g3960__2802(.A1 (n_54), .A2 (MAC[27]), .B1 (ByteCnt[3]), .B2
       (ByteCnt[4]), .Z (n_66));
  AO21D2 g3961__1705(.A1 (n_135), .A2 (n_51), .B (TxReset), .Z
       (ResetByteCnt));
  NR2D1 g3962__5122(.A1 (n_64), .A2 (ByteCnt[3]), .ZN (n_69));
  AN2XD1 g3963__8246(.A1 (n_62), .A2 (n_56), .Z (n_68));
  CKND1 g3964(.I (n_63), .ZN (n_62));
  ND2D1 g3965__7098(.A1 (DlyCrcEn), .A2 (n_141), .ZN (n_65));
  IND2D1 g3966__6131(.A1 (ByteCnt[2]), .B1 (n_58), .ZN (n_64));
  ND2D1 g3967__1881(.A1 (n_58), .A2 (ByteCnt[2]), .ZN (n_63));
  CKND1 g3968(.I (n_61), .ZN (n_134));
  AOI21D1 g3969__5115(.A1 (MAC[23]), .A2 (ByteCnt[1]), .B (n_53), .ZN
       (n_59));
  NR2XD0 g3970__7482(.A1 (n_51), .A2 (TxCtrlStartFrm_q), .ZN (n_61));
  NR3D1 g3971__4733(.A1 (ByteCnt[2]), .A2 (ByteCnt[0]), .A3
       (ByteCnt[3]), .ZN (n_60));
  NR2XD0 g3974__6161(.A1 (MAC[31]), .A2 (ByteCnt[3]), .ZN (n_57));
  OR2XD1 g3975__9315(.A1 (TxAbortIn), .A2 (TxDoneIn), .Z (n_135));
  NR2XD1 g3976__9945(.A1 (ByteCnt[0]), .A2 (ByteCnt[5]), .ZN (n_58));
  CKND1 g3977(.I (n_55), .ZN (n_137));
  INVD1 g3978(.I (n_54), .ZN (n_138));
  CKND1 g3979(.I (n_53), .ZN (n_140));
  NR2XD0 g3980__2883(.A1 (MAC[0]), .A2 (ByteCnt[3]), .ZN (n_52));
  CKND2D1 g3981__2346(.A1 (DlyCrcCnt[1]), .A2 (DlyCrcCnt[0]), .ZN
       (n_141));
  AN2XD1 g3982__1666(.A1 (n_48), .A2 (n_4), .Z (n_56));
  AN2XD1 g3983__7410(.A1 (ByteCnt[4]), .A2 (ByteCnt[1]), .Z (n_55));
  AN2XD1 g3984__6417(.A1 (n_4), .A2 (ByteCnt[4]), .Z (n_54));
  AN2D2 g3985__5477(.A1 (n_48), .A2 (ByteCnt[1]), .Z (n_53));
  CKND1 g3986(.I (TxCtrlStartFrm), .ZN (n_51));
  INVD1 g3988(.I (TxReset), .ZN (n_1));
  CKND1 drc_bufs(.I (n_45), .ZN (n_47));
  INVD1 drc_bufs3992(.I (n_69), .ZN (n_45));
  BUFFD0 drc(.I (n_75), .Z (n_46));
  NR2XD0 g2570__2398(.A1 (n_43), .A2 (ResetByteCnt), .ZN (n_44));
  MAOI22D1 g2572__5107(.A1 (n_39), .A2 (ByteCnt[3]), .B1 (n_39), .B2
       (ByteCnt[3]), .ZN (n_43));
  OA211D1 g2573__6260(.A1 (ByteCnt[2]), .A2 (n_32), .B (n_39), .C
       (n_2), .Z (n_42));
  NR2XD0 g2577__4319(.A1 (n_37), .A2 (ResetByteCnt), .ZN (n_41));
  NR2XD0 g2578__8428(.A1 (n_36), .A2 (ResetByteCnt), .ZN (n_40));
  AOI211XD0 g2579__5526(.A1 (n_21), .A2 (n_4), .B (n_32), .C
       (ResetByteCnt), .ZN (n_38));
  CKND2D1 g2580__6783(.A1 (n_32), .A2 (ByteCnt[2]), .ZN (n_39));
  OA211D1 g2581__3680(.A1 (n_140), .A2 (n_33), .B (n_35), .C (n_138),
       .Z (n_37));
  XNR2D1 g2582__1617(.A1 (n_34), .A2 (ByteCnt[5]), .ZN (n_36));
  SDFCNQD2 TxCtrlStartFrm_reg(.CDN (n_1), .CP (MTxClk), .D
       (TxCtrlStartFrm), .SI (n_10), .SE (n_26), .Q (TxCtrlStartFrm));
  CKND2D1 g2585__2802(.A1 (n_33), .A2 (ByteCnt[4]), .ZN (n_35));
  NR2XD0 g2586__1705(.A1 (n_33), .A2 (n_137), .ZN (n_34));
  NR2XD0 g2590__5122(.A1 (n_27), .A2 (ResetByteCnt), .ZN (n_31));
  OR2D1 g2591__8246(.A1 (n_21), .A2 (n_12), .Z (n_33));
  NR2XD1 g2592__7098(.A1 (n_21), .A2 (n_4), .ZN (n_32));
  DFCNQD1 SendingCtrlFrm_reg(.CDN (n_1), .CP (MTxClk), .D (n_25), .Q
       (SendingCtrlFrm));
  SDFCNQD1 WillSendControlFrame_reg(.CDN (n_1), .CP (MTxClk), .D (n_8),
       .SI (WillSendControlFrame), .SE (n_14), .Q
       (WillSendControlFrame));
  SDFCNQD4 CtrlMux_reg(.CDN (n_1), .CP (MTxClk), .D (n_9), .SI
       (CtrlMux), .SE (n_18), .Q (CtrlMux));
  NR2XD0 g2596__6131(.A1 (n_23), .A2 (ResetByteCnt), .ZN (n_30));
  NR2XD0 g2597__1881(.A1 (n_22), .A2 (ResetByteCnt), .ZN (n_29));
  NR2XD0 g2598__5115(.A1 (n_24), .A2 (ResetByteCnt), .ZN (n_28));
  AOI21D1 g2599__7482(.A1 (n_17), .A2 (ByteCnt[0]), .B (n_21), .ZN
       (n_27));
  ND2D1 g2600__4733(.A1 (n_0), .A2 (n_10), .ZN (n_26));
  SDFCNQD1 BlockTxDone_reg(.CDN (n_1), .CP (MTxClk), .D
       (TxCtrlStartFrm), .SI (BlockTxDone), .SE (n_7), .Q
       (BlockTxDone));
  MOAI22D1 g2602__6161(.A1 (n_19), .A2 (n_13), .B1 (n_19), .B2
       (SendingCtrlFrm), .ZN (n_25));
  MAOI22D1 g2603__9315(.A1 (n_16), .A2 (DlyCrcCnt[2]), .B1 (n_16), .B2
       (n_141), .ZN (n_24));
  MAOI22D1 g2604__9945(.A1 (n_16), .A2 (DlyCrcCnt[0]), .B1 (n_16), .B2
       (DlyCrcCnt[0]), .ZN (n_23));
  MAOI22D1 g2605__2883(.A1 (n_16), .A2 (DlyCrcCnt[1]), .B1 (n_15), .B2
       (n_16), .ZN (n_22));
  NR2XD1 g2606__2346(.A1 (n_17), .A2 (ByteCnt[0]), .ZN (n_21));
  OAI31D1 g2607__1666(.A1 (TxStartFrmIn), .A2 (n_132), .A3 (n_135), .B
       (n_9), .ZN (n_20));
  DFCNQD1 TxCtrlEndFrm_reg(.CDN (n_1), .CP (MTxClk), .D (n_11), .Q
       (TxCtrlEndFrm));
  NR2XD0 g2609__7410(.A1 (n_9), .A2 (TxDoneIn), .ZN (n_18));
  INR2XD0 g2610__6417(.A1 (n_13), .B1 (TxDoneIn), .ZN (n_19));
  XNR2D1 g2611__5477(.A1 (DlyCrcCnt[0]), .A2 (DlyCrcCnt[1]), .ZN
       (n_15));
  INR3D1 g2612__2398(.A1 (TxUsedDataIn), .B1 (n_134), .B2 (n_136), .ZN
       (n_17));
  AOI22D1 g2613__5107(.A1 (TxFlow), .A2 (TPauseRq), .B1 (TxCtrlEndFrm),
       .B2 (CtrlMux), .ZN (n_14));
  OR3XD1 g2614__6260(.A1 (n_6), .A2 (DlyCrcCnt[2]), .A3 (n_3), .Z
       (n_16));
  ND2D1 g2615__4319(.A1 (ByteCnt[3]), .A2 (ByteCnt[2]), .ZN (n_12));
  IND2D1 g2616__8428(.A1 (ControlEnd_q), .B1 (n_139), .ZN (n_11));
  ND2D1 g2617__5526(.A1 (WillSendControlFrame), .A2 (TxCtrlStartFrm),
       .ZN (n_13));
  CKND2D1 g2618__6783(.A1 (CtrlMux), .A2 (TxUsedDataIn_q), .ZN (n_10));
  ND2D1 g2619__3680(.A1 (TxCtrlEndFrm), .A2 (CtrlMux), .ZN (n_8));
  NR2XD0 g2620__1617(.A1 (TxCtrlStartFrm), .A2 (TxStartFrmIn), .ZN
       (n_7));
  INR2XD1 g2621__2802(.A1 (WillSendControlFrame), .B1 (TxUsedDataOut),
       .ZN (n_9));
  CKND1 g2622(.I (TxUsedDataIn), .ZN (n_6));
  CKND1 g2627(.I (CtrlMux), .ZN (n_3));
  BUFFD0 drc3995(.I (n_20), .Z (n_0));
  INVD1 g1482(.I (RxByteCntEq0), .ZN (n_131));
  INVD1 g1481(.I (Transmitting), .ZN (n_130));
  CKND0 g1483(.I (r_RecSmall), .ZN (n_129));
  DFCNQD2 LoadRxStatus_reg(.CDN (n_4), .CP (MRxClk), .D (n_231), .Q
       (LoadRxStatus));
  DFCNQD2 ReceiveEnd_reg(.CDN (n_4), .CP (MRxClk), .D (LoadRxStatus),
       .Q (ReceiveEnd));
  AN2XD1 g2462__1705(.A1 (n_135), .A2 (n_134), .Z (ReceivedLengthOK));
  AO221D0 g2463__5122(.A1 (n_128), .A2 (n_80), .B1 (n_87), .B2
       (RxByteCnt[14]), .C (n_116), .Z (n_135));
  AO31D1 g2464__8246(.A1 (n_127), .A2 (n_79), .A3 (n_70), .B (n_118),
       .Z (n_134));
  AOI211XD0 g2465__7098(.A1 (n_60), .A2 (r_MinFL[12]), .B (n_43), .C
       (n_69), .ZN (n_128));
  OA22D0 g2466__6131(.A1 (n_125), .A2 (n_117), .B1 (r_MaxFL[12]), .B2
       (n_60), .Z (n_127));
  AOI211XD0 g2467__1881(.A1 (n_104), .A2 (RxByteCnt[8]), .B (n_124), .C
       (n_89), .ZN (n_126));
  OAI222D1 g2468__5115(.A1 (n_230), .A2 (n_113), .B1 (RxByteCnt[9]),
       .B2 (n_42), .C1 (RxByteCnt[11]), .C2 (n_55), .ZN (n_125));
  OAI221D1 g2469__7482(.A1 (n_123), .A2 (n_108), .B1 (r_MinFL[11]), .B2
       (n_53), .C (n_100), .ZN (n_124));
  OA211D1 g2470__4733(.A1 (r_MinFL[7]), .A2 (n_63), .B (n_235), .C
       (n_115), .Z (n_123));
  OAI31D1 g2472__6161(.A1 (n_67), .A2 (n_109), .A3 (n_110), .B (n_107),
       .ZN (n_121));
  AOI211XD0 g2473__9315(.A1 (n_94), .A2 (RxByteCnt[5]), .B (n_119), .C
       (n_91), .ZN (n_120));
  OA211D1 g2474__9945(.A1 (RxByteCnt[3]), .A2 (n_58), .B (n_111), .C
       (n_112), .Z (n_119));
  AO221D0 g2475__2883(.A1 (n_98), .A2 (n_79), .B1 (n_52), .B2
       (r_MaxFL[15]), .C (n_90), .Z (n_118));
  MOAI22D1 g2476__2346(.A1 (n_85), .A2 (RxByteCnt[10]), .B1 (n_105),
       .B2 (r_MaxFL[8]), .ZN (n_117));
  MOAI22D1 g2477__1666(.A1 (n_52), .A2 (r_MinFL[15]), .B1 (n_44), .B2
       (n_80), .ZN (n_116));
  CKND2D1 g2478__7410(.A1 (n_103), .A2 (RxByteCnt[4]), .ZN (n_115));
  AOI21D1 g2481__6417(.A1 (n_97), .A2 (r_MaxFL[8]), .B (n_105), .ZN
       (n_113));
  OAI221D1 g2482__5477(.A1 (n_64), .A2 (r_MinFL[2]), .B1 (r_MinFL[3]),
       .B2 (n_51), .C (n_102), .ZN (n_112));
  AO21D1 g2483__2398(.A1 (n_96), .A2 (RxByteCnt[4]), .B (n_103), .Z
       (n_111));
  AOI21D1 g2484__5107(.A1 (n_93), .A2 (r_MaxFL[4]), .B (n_106), .ZN
       (n_110));
  AOI211XD0 g2485__6260(.A1 (n_64), .A2 (r_MaxFL[2]), .B (n_101), .C
       (n_68), .ZN (n_109));
  AOI21D1 g2486__4319(.A1 (n_92), .A2 (RxByteCnt[8]), .B (n_104), .ZN
       (n_108));
  AOI33D1 g2487__8428(.A1 (n_82), .A2 (n_49), .A3 (r_MaxFL[5]), .B1
       (n_75), .B2 (n_50), .B3 (r_MaxFL[6]), .ZN (n_107));
  INR2XD0 g2488__5526(.A1 (n_93), .B1 (RxByteCnt[4]), .ZN (n_106));
  INR2XD0 g2489__6783(.A1 (n_97), .B1 (RxByteCnt[8]), .ZN (n_105));
  INR2XD0 g2491__3680(.A1 (n_92), .B1 (r_MinFL[8]), .ZN (n_104));
  INR2XD0 g2492__1617(.A1 (n_96), .B1 (r_MinFL[4]), .ZN (n_103));
  OAI222D1 g2493__2802(.A1 (n_84), .A2 (RxByteCnt[0]), .B1
       (RxByteCnt[1]), .B2 (n_66), .C1 (RxByteCnt[2]), .C2 (n_65), .ZN
       (n_102));
  OA221D0 g2494__1705(.A1 (n_48), .A2 (r_MaxFL[1]), .B1 (r_MaxFL[2]),
       .B2 (n_64), .C (n_95), .Z (n_101));
  IND3D1 g2495__5122(.A1 (r_MinFL[9]), .B1 (RxByteCnt[9]), .B2 (n_83),
       .ZN (n_100));
  OAI31D1 g2496__8246(.A1 (r_MinFL[12]), .A2 (n_60), .A3 (n_69), .B
       (n_76), .ZN (n_99));
  AO32D1 g2497__7098(.A1 (n_70), .A2 (n_60), .A3 (r_MaxFL[12]), .B1
       (n_61), .B2 (r_MaxFL[13]), .Z (n_98));
  AO211D1 g2498__6131(.A1 (n_48), .A2 (r_MaxFL[1]), .B (n_56), .C
       (r_MaxFL[0]), .Z (n_95));
  NR2XD0 g2499__1881(.A1 (n_88), .A2 (r_MinFL[5]), .ZN (n_94));
  AOI21D1 g2501__5115(.A1 (n_54), .A2 (RxByteCnt[9]), .B (n_81), .ZN
       (n_97));
  AOI21D1 g2502__7482(.A1 (n_49), .A2 (r_MinFL[5]), .B (n_88), .ZN
       (n_96));
  NR3D0 g2503__4733(.A1 (n_74), .A2 (n_50), .A3 (r_MinFL[6]), .ZN
       (n_91));
  INR3D0 g2504__6161(.A1 (r_MaxFL[14]), .B1 (RxByteCnt[14]), .B2
       (n_72), .ZN (n_90));
  INR3D0 g2505__9315(.A1 (RxByteCnt[10]), .B1 (r_MinFL[10]), .B2
       (n_71), .ZN (n_89));
  OA21D1 g2506__9945(.A1 (n_49), .A2 (r_MaxFL[5]), .B (n_82), .Z
       (n_93));
  OA21D1 g2507__2883(.A1 (n_59), .A2 (RxByteCnt[9]), .B (n_83), .Z
       (n_92));
  NR2XD0 g2509__2346(.A1 (n_78), .A2 (r_MinFL[14]), .ZN (n_87));
  CKND2D1 g2511__1666(.A1 (n_77), .A2 (r_MaxFL[10]), .ZN (n_85));
  OAI21D1 g2512__7410(.A1 (n_48), .A2 (r_MinFL[1]), .B (r_MinFL[0]),
       .ZN (n_84));
  AO21D1 g2513__6417(.A1 (n_50), .A2 (r_MinFL[6]), .B (n_74), .Z
       (n_88));
  AOI21D1 g2515__5477(.A1 (n_47), .A2 (r_MinFL[10]), .B (n_71), .ZN
       (n_83));
  OA21D1 g2516__2398(.A1 (n_50), .A2 (r_MaxFL[6]), .B (n_75), .Z
       (n_82));
  OAI21D1 g2517__5107(.A1 (n_47), .A2 (r_MaxFL[10]), .B (n_77), .ZN
       (n_81));
  AOI21D1 g2518__6260(.A1 (n_62), .A2 (r_MinFL[14]), .B (n_78), .ZN
       (n_80));
  AOI21D1 g2519__4319(.A1 (n_57), .A2 (RxByteCnt[14]), .B (n_72), .ZN
       (n_79));
  IND2D1 g2520__8428(.A1 (r_MinFL[13]), .B1 (RxByteCnt[13]), .ZN
       (n_76));
  INR2D1 g2527__5526(.A1 (r_MinFL[15]), .B1 (RxByteCnt[15]), .ZN
       (n_78));
  ND2D1 g2528__6783(.A1 (n_55), .A2 (RxByteCnt[11]), .ZN (n_77));
  CKND1 g2529(.I (n_73), .ZN (n_133));
  AN2XD1 g2530__3680(.A1 (n_51), .A2 (r_MaxFL[3]), .Z (n_68));
  NR2D1 g2531__1617(.A1 (n_51), .A2 (r_MaxFL[3]), .ZN (n_67));
  OR2XD1 g2532__2802(.A1 (StartTxDone), .A2 (StartTxAbort), .Z (n_136));
  IND2D1 g2533__1705(.A1 (r_MaxFL[7]), .B1 (RxByteCnt[7]), .ZN (n_75));
  INR2D1 g2534__5122(.A1 (r_MinFL[7]), .B1 (RxByteCnt[7]), .ZN (n_74));
  NR2XD0 g2535__8246(.A1 (RxStateData[0]), .A2 (RxStateData[1]), .ZN
       (n_73));
  NR2D1 g2536__7098(.A1 (n_52), .A2 (r_MaxFL[15]), .ZN (n_72));
  INR2D1 g2537__6131(.A1 (r_MinFL[11]), .B1 (RxByteCnt[11]), .ZN
       (n_71));
  IND2D1 g2538__1881(.A1 (r_MaxFL[13]), .B1 (RxByteCnt[13]), .ZN
       (n_70));
  INR2D1 g2539__5115(.A1 (r_MinFL[13]), .B1 (RxByteCnt[13]), .ZN
       (n_69));
  CKND1 g2540(.I (r_MinFL[1]), .ZN (n_66));
  CKND1 g2541(.I (r_MinFL[2]), .ZN (n_65));
  CKND1 g2542(.I (RxByteCnt[2]), .ZN (n_64));
  CKND1 g2543(.I (RxByteCnt[7]), .ZN (n_63));
  CKND1 g2544(.I (RxByteCnt[14]), .ZN (n_62));
  CKND1 g2545(.I (RxByteCnt[13]), .ZN (n_61));
  CKND1 g2546(.I (RxByteCnt[12]), .ZN (n_60));
  CKND1 g2547(.I (r_MinFL[9]), .ZN (n_59));
  CKND1 g2548(.I (r_MinFL[3]), .ZN (n_58));
  CKND1 g2549(.I (r_MaxFL[14]), .ZN (n_57));
  CKND1 g2550(.I (RxByteCnt[0]), .ZN (n_56));
  CKND1 g2551(.I (r_MaxFL[11]), .ZN (n_55));
  CKND1 g2552(.I (r_MaxFL[9]), .ZN (n_54));
  CKND1 g2553(.I (RxByteCnt[11]), .ZN (n_53));
  CKND1 g2554(.I (RxByteCnt[15]), .ZN (n_52));
  CKND1 g2555(.I (RxByteCnt[3]), .ZN (n_51));
  CKND1 g2556(.I (RxByteCnt[6]), .ZN (n_50));
  CKND1 g2557(.I (RxByteCnt[5]), .ZN (n_49));
  CKND1 g2558(.I (RxByteCnt[1]), .ZN (n_48));
  CKND1 g2559(.I (RxByteCnt[10]), .ZN (n_47));
  INVD1 g2560(.I (Reset), .ZN (n_4));
  BUFFD0 drc(.I (n_121), .Z (n_45));
  BUFFD0 drc2561(.I (n_99), .Z (n_44));
  BUFFD0 drc2562(.I (n_126), .Z (n_43));
  IND2D1 g2__7482(.A1 (n_81), .B1 (r_MaxFL[9]), .ZN (n_42));
  SDFSNQD1 RxColWindow_reg(.SDN (n_4), .CP (MRxClk), .D (n_40), .SI
       (RxColWindow), .SE (n_41), .Q (RxColWindow));
  INR2XD0 g1928__4733(.A1 (n_40), .B1 (RxStateIdle), .ZN (n_41));
  SDFCNQD1 CarrierSenseLost_reg(.CDN (n_4), .CP (MTxClk), .D (n_36),
       .SI (CarrierSenseLost), .SE (n_37), .Q (CarrierSenseLost));
  IND3D1 g1930__6161(.A1 (Collision), .B1 (RxStateData[1]), .B2 (n_1),
       .ZN (n_40));
  SDFCNQD1 InvalidSymbol_reg(.CDN (n_4), .CP (MRxClk), .D
       (InvalidSymbol), .SI (n_35), .SE (n_0), .Q (InvalidSymbol));
  DFCNQD1 RxLateCollision_reg(.CDN (n_4), .CP (MRxClk), .D (n_38), .Q
       (RxLateCollision));
  AOI211XD0 g1933__9315(.A1 (n_3), .A2 (CollValid[4]), .B (n_33), .C
       (n_9), .ZN (n_39));
  DFCNQD1 LatchedMRxErr_reg(.CDN (n_4), .CP (MRxClk), .D (n_34), .Q
       (LatchedMRxErr));
  MOAI22D1 g1935__9945(.A1 (n_29), .A2 (LoadRxStatus), .B1 (n_29), .B2
       (RxLateCollision), .ZN (n_38));
  NR2XD0 g1936__2883(.A1 (n_36), .A2 (TxStartFrm), .ZN (n_37));
  DFCNQD1 LatchedCrcError_reg(.CDN (n_4), .CP (MRxClk), .D (n_30), .Q
       (LatchedCrcError));
  DFCNQD1 DribbleNibble_reg(.CDN (n_4), .CP (MRxClk), .D (n_26), .Q
       (DribbleNibble));
  DFCNQD1 DeferLatched_reg(.CDN (n_4), .CP (MTxClk), .D (n_28), .Q
       (DeferLatched));
  DFCNQD1 ReceivedPacketTooBig_reg(.CDN (n_4), .CP (MRxClk), .D (n_31),
       .Q (ReceivedPacketTooBig));
  CKND2D1 g1941__2346(.A1 (n_32), .A2 (LoadRxStatus), .ZN (n_35));
  OA211D1 g1942__1666(.A1 (RxStateSFD), .A2 (n_15), .B (MRxDV), .C
       (MRxErr), .Z (n_34));
  OAI211D1 g1943__7410(.A1 (CollValid[4]), .A2 (n_3), .B (n_23), .C
       (n_24), .ZN (n_33));
  NR2D1 g1944__6417(.A1 (n_27), .A2 (Collision), .ZN (n_36));
  NR2XD0 g1946__5477(.A1 (n_21), .A2 (LoadRxStatus), .ZN (n_31));
  NR2XD0 g1947__2398(.A1 (n_22), .A2 (RxStateSFD), .ZN (n_30));
  IND3D1 g1948__5107(.A1 (n_18), .B1 (MRxErr), .B2 (MRxDV), .ZN (n_32));
  DFCNQD1 ShortFrame_reg(.CDN (n_4), .CP (MRxClk), .D (n_25), .Q
       (ShortFrame));
  MOAI22D1 g1950__6260(.A1 (n_19), .A2 (n_8), .B1 (n_19), .B2
       (DeferLatched), .ZN (n_28));
  OR4D1 g1951__4319(.A1 (Loopback), .A2 (CarrierSense), .A3 (r_FullD),
       .A4 (n_17), .Z (n_27));
  MOAI22D1 g1952__8428(.A1 (n_20), .A2 (RxStateSFD), .B1 (n_20), .B2
       (DribbleNibble), .ZN (n_26));
  AOI21D1 g1953__5526(.A1 (n_16), .A2 (Collision), .B (LoadRxStatus),
       .ZN (n_29));
  NR2XD0 g1954__6783(.A1 (n_12), .A2 (LoadRxStatus), .ZN (n_25));
  NR2XD0 g1955__3680(.A1 (n_14), .A2 (n_13), .ZN (n_24));
  NR2XD0 g1956__1617(.A1 (n_10), .A2 (n_11), .ZN (n_23));
  AOI32D1 g1957__2802(.A1 (RxCrcError), .A2 (n_131), .A3
       (RxStateData[0]), .B1 (LatchedCrcError), .B2 (n_6), .ZN (n_22));
  MUX2ND0 g1958__1705(.I0 (ReceivedPacketTooBig), .I1 (n_7), .S
       (n_231), .ZN (n_21));
  IND4D1 g1959__5122(.A1 (MRxD[0]), .B1 (MRxD[3]), .B2 (MRxD[2]), .B3
       (MRxD[1]), .ZN (n_18));
  NR3D0 g1960__8246(.A1 (StateData[1]), .A2 (StateData[0]), .A3
       (StatePreamble), .ZN (n_17));
  AOI21D1 g1961__7098(.A1 (n_129), .A2 (RxColWindow), .B (r_FullD), .ZN
       (n_16));
  AO211D1 g1962__6131(.A1 (n_130), .A2 (RxStateIdle), .B (n_133), .C
       (RxStatePreamble), .Z (n_15));
  AOI21D1 g1963__1881(.A1 (n_2), .A2 (RxStateData[1]), .B (RxStateSFD),
       .ZN (n_20));
  INR2XD0 g1964__5115(.A1 (n_8), .B1 (TxStartFrm), .ZN (n_19));
  MAOI22D1 g1965__7482(.A1 (RxByteCnt[5]), .A2 (CollValid[5]), .B1
       (RxByteCnt[5]), .B2 (CollValid[5]), .ZN (n_14));
  MAOI22D1 g1966__4733(.A1 (RxByteCnt[2]), .A2 (CollValid[2]), .B1
       (RxByteCnt[2]), .B2 (CollValid[2]), .ZN (n_13));
  MAOI22D1 g1967__6161(.A1 (n_5), .A2 (ShortFrame), .B1 (n_135), .B2
       (n_5), .ZN (n_12));
  CKXOR2D1 g1968__9315(.A1 (RxByteCnt[1]), .A2 (CollValid[1]), .Z
       (n_11));
  CKXOR2D1 g1969__9945(.A1 (RxByteCnt[0]), .A2 (CollValid[0]), .Z
       (n_10));
  CKXOR2D1 g1970__2883(.A1 (RxByteCnt[3]), .A2 (CollValid[3]), .Z
       (n_9));
  ND2D1 g1971__2346(.A1 (DeferIndication), .A2 (TxUsedData), .ZN (n_8));
  NR2XD0 g1972__1666(.A1 (n_134), .A2 (r_HugEn), .ZN (n_7));
  CKND1 g1973(.I (RxStateData[0]), .ZN (n_6));
  CKND1 g1974(.I (n_231), .ZN (n_5));
  CKND1 g1976(.I (RxByteCnt[4]), .ZN (n_3));
  CKND1 g1977(.I (MRxDV), .ZN (n_2));
  BUFFD0 drc2563(.I (n_39), .Z (n_1));
  IND2D1 g2564__7410(.A1 (LoadRxStatus), .B1 (n_32), .ZN (n_0));
  AOI221D2 g2565__6417(.A1 (n_106), .A2 (r_MaxFL[4]), .B1 (n_63), .B2
       (r_MaxFL[7]), .C (n_45), .ZN (n_230));
  IOA22D2 g2566__5477(.A1 (RxByteCntMaxFrame), .A2 (RxStateData[0]),
       .B1 (MRxDV), .B2 (n_73), .ZN (n_231));
  BUFFD0 drc2569(.I (n_120), .Z (n_235));
  INVD1 g1958(.I (n_181), .ZN (n_129));
  CKND1 g1959(.I (n_182), .ZN (n_128));
  DFCNQD1 EndBusy_d_reg(.CDN (n_4), .CP (Clk), .D (n_78), .Q
       (EndBusy_d));
  DFCNQD2 EndBusy_reg(.CDN (n_4), .CP (Clk), .D (EndBusy_d), .Q
       (EndBusy));
  DFCNQD1 RStat_q1_reg(.CDN (n_4), .CP (Clk), .D (RStat), .Q
       (RStat_q1));
  DFCNQD1 RStat_q2_reg(.CDN (n_4), .CP (Clk), .D (RStat_q1), .Q
       (RStat_q2));
  DFCNQD1 ScanStat_q1_reg(.CDN (n_4), .CP (Clk), .D (ScanStat), .Q
       (ScanStat_q1));
  DFCNQD1 WCtrlData_q1_reg(.CDN (n_4), .CP (Clk), .D (WCtrlData), .Q
       (WCtrlData_q1));
  DFCNQD1 WCtrlData_q2_reg(.CDN (n_4), .CP (Clk), .D (WCtrlData_q1), .Q
       (WCtrlData_q2));
  OR2XD1 g3022__2398(.A1 (outctrl_Mdo_2d), .A2 (ShiftedBit), .Z
       (n_127));
  AO221D0 g3024__5107(.A1 (n_112), .A2 (shftrg_ShiftReg[6]), .B1
       (n_88), .B2 (Fiad[0]), .C (n_93), .Z (n_126));
  ND3D1 g3028__6260(.A1 (n_124), .A2 (n_105), .A3 (n_94), .ZN (n_125));
  AOI22D1 g3029__4319(.A1 (n_112), .A2 (shftrg_ShiftReg[5]), .B1
       (n_88), .B2 (Rgad[4]), .ZN (n_124));
  ND2D1 g3033__8428(.A1 (n_122), .A2 (n_95), .ZN (n_123));
  AOI21D1 g3034__5526(.A1 (n_112), .A2 (shftrg_ShiftReg[4]), .B
       (n_108), .ZN (n_122));
  ND2D1 g3038__6783(.A1 (n_120), .A2 (n_96), .ZN (n_121));
  AOI21D1 g3039__3680(.A1 (n_112), .A2 (shftrg_ShiftReg[3]), .B
       (n_111), .ZN (n_120));
  ND2D1 g3043__1617(.A1 (n_118), .A2 (n_97), .ZN (n_119));
  AOI21D1 g3044__2802(.A1 (n_112), .A2 (shftrg_ShiftReg[2]), .B
       (n_110), .ZN (n_118));
  ND2D1 g3048__1705(.A1 (n_116), .A2 (n_98), .ZN (n_117));
  AOI21D1 g3049__5122(.A1 (n_112), .A2 (shftrg_ShiftReg[1]), .B
       (n_109), .ZN (n_116));
  IND3D1 g3053__8246(.A1 (n_88), .B1 (n_100), .B2 (n_114), .ZN (n_115));
  AOI22D1 g3054__7098(.A1 (n_112), .A2 (shftrg_ShiftReg[0]), .B1
       (n_104), .B2 (Fiad[2]), .ZN (n_114));
  AO221D0 g3058__6131(.A1 (n_112), .A2 (Mdi), .B1 (n_104), .B2
       (Fiad[1]), .C (n_99), .Z (n_113));
  AN4XD1 g3060__1881(.A1 (n_112), .A2 (MdcEn_n), .A3 (n_102), .A4
       (LatchByte[1]), .Z (shftrg_n_107));
  ND3D1 g3061__5115(.A1 (n_112), .A2 (MdcEn_n), .A3 (LatchByte[0]), .ZN
       (n_181));
  AN4D2 g3063__7482(.A1 (n_105), .A2 (n_83), .A3 (n_85), .A4 (n_87), .Z
       (n_112));
  OR4D1 g3066__4733(.A1 (EndBusy), .A2 (SyncStatMdcEn), .A3
       (InProgress), .A4 (n_101), .Z (Busy));
  AO22D0 g3067__6161(.A1 (n_104), .A2 (WriteOp), .B1 (CtrlData[12]),
       .B2 (n_84), .Z (n_111));
  AO22D0 g3068__9315(.A1 (n_104), .A2 (Fiad[4]), .B1 (CtrlData[11]),
       .B2 (n_84), .Z (n_110));
  AO22D0 g3069__9945(.A1 (n_104), .A2 (Fiad[3]), .B1 (CtrlData[10]),
       .B2 (n_84), .Z (n_109));
  MOAI22D1 g3070__2883(.A1 (n_105), .A2 (WriteOp), .B1 (n_86), .B2
       (CtrlData[5]), .ZN (n_108));
  INR2XD0 g3071__2346(.A1 (n_70), .B1 (n_103), .ZN (n_107));
  AO21D1 g3072__1666(.A1 (n_70), .A2 (InProgress), .B (n_103), .Z
       (n_106));
  CKND1 g3073(.I (n_105), .ZN (n_104));
  OA31D1 g3074__7410(.A1 (BitCounter[4]), .A2 (n_133), .A3 (n_82), .B
       (n_132), .Z (n_105));
  CKND2D1 g3075__6417(.A1 (n_132), .A2 (n_91), .ZN (n_103));
  OR4D1 g3077__5477(.A1 (WCtrlData), .A2 (RStat), .A3 (RStatStart), .A4
       (n_79), .Z (n_101));
  AOI22D1 g3078__2398(.A1 (n_84), .A2 (CtrlData[9]), .B1 (n_86), .B2
       (CtrlData[1]), .ZN (n_100));
  AO22D0 g3080__5107(.A1 (n_84), .A2 (CtrlData[8]), .B1 (CtrlData[0]),
       .B2 (n_86), .Z (n_99));
  ND2D1 g3082__6260(.A1 (n_92), .A2 (InProgress), .ZN (n_132));
  AOI22D1 g3083__4319(.A1 (n_86), .A2 (CtrlData[2]), .B1 (n_88), .B2
       (Rgad[0]), .ZN (n_98));
  AOI22D1 g3084__8428(.A1 (n_86), .A2 (CtrlData[3]), .B1 (n_88), .B2
       (Rgad[1]), .ZN (n_97));
  AOI22D1 g3085__5526(.A1 (n_86), .A2 (CtrlData[4]), .B1 (n_88), .B2
       (Rgad[2]), .ZN (n_96));
  AOI22D1 g3086__6783(.A1 (n_84), .A2 (CtrlData[13]), .B1 (n_88), .B2
       (Rgad[3]), .ZN (n_95));
  AOI22D1 g3087__3680(.A1 (n_84), .A2 (CtrlData[14]), .B1 (n_86), .B2
       (CtrlData[6]), .ZN (n_94));
  AO22D0 g3088__1617(.A1 (n_84), .A2 (CtrlData[15]), .B1 (CtrlData[7]),
       .B2 (n_86), .Z (n_93));
  NR3D0 g3091__2802(.A1 (n_80), .A2 (BitCounter[5]), .A3
       (BitCounter[4]), .ZN (n_92));
  AO211D1 g3092__1705(.A1 (n_77), .A2 (n_67), .B (n_70), .C (n_5), .Z
       (n_91));
  NR2XD0 g3093__5122(.A1 (n_81), .A2 (BitCounter[3]), .ZN (n_90));
  NR2XD0 g3094__8246(.A1 (n_81), .A2 (n_65), .ZN (n_89));
  CKND1 g3096(.I (n_88), .ZN (n_87));
  CKND1 g3097(.I (n_86), .ZN (n_85));
  CKND1 g3098(.I (n_84), .ZN (n_83));
  AN4D2 g3099__7098(.A1 (n_75), .A2 (n_69), .A3 (n_66), .A4
       (BitCounter[3]), .Z (n_88));
  AN4D2 g3100__6131(.A1 (n_73), .A2 (n_75), .A3 (WriteOp), .A4
       (BitCounter[3]), .Z (n_86));
  AN3D2 g3101__1881(.A1 (n_76), .A2 (n_73), .A3 (WriteOp), .Z (n_84));
  IND2D1 g3103__5115(.A1 (NoPre), .B1 (n_76), .ZN (n_82));
  INR2XD1 g3104__7482(.A1 (Mdc), .B1 (clkgen_n_104), .ZN (MdcEn_n));
  OR2D1 g3105__4733(.A1 (clkgen_n_104), .A2 (Mdc), .Z (n_182));
  ND2D1 g3106__6161(.A1 (n_76), .A2 (NoPre), .ZN (n_80));
  OR3D1 g3107__9315(.A1 (InProgress_q3), .A2 (Nvalid), .A3
       (WCtrlDataStart), .Z (n_79));
  OR3D1 g3108__9945(.A1 (WriteOp), .A2 (n_134), .A3 (n_137), .Z (n_81));
  CKND1 g3109(.I (n_139), .ZN (n_78));
  IND3D1 g3110__2883(.A1 (BitCounter[6]), .B1 (outctrl_n_49), .B2
       (n_72), .ZN (n_77));
  IND2D1 g3111__2346(.A1 (InProgress_q2), .B1 (InProgress_q3), .ZN
       (n_139));
  AN2XD1 g3112__2398(.A1 (n_75), .A2 (n_65), .Z (n_76));
  OR4D2 g3113__5107(.A1 (clkgen_Counter[1]), .A2 (clkgen_Counter[6]),
       .A3 (clkgen_Counter[0]), .A4 (n_71), .Z (clkgen_n_104));
  OR2D1 g3118__6260(.A1 (n_74), .A2 (BitCounter[6]), .Z (n_137));
  INR3D1 g3119__4319(.A1 (n_68), .B1 (BitCounter[2]), .B2
       (BitCounter[6]), .ZN (n_75));
  CKND1 g3125(.I (n_73), .ZN (n_134));
  ND3D1 g3126__8428(.A1 (BitCounter[1]), .A2 (BitCounter[2]), .A3
       (BitCounter[3]), .ZN (n_72));
  OR4D1 g3127__5526(.A1 (clkgen_Counter[5]), .A2 (clkgen_Counter[4]),
       .A3 (clkgen_Counter[2]), .A4 (clkgen_Counter[3]), .Z (n_71));
  IND2D1 g3128__6783(.A1 (n_136), .B1 (BitCounter[2]), .ZN (n_74));
  NR2D2 g3130__3680(.A1 (outctrl_n_49), .A2 (n_5), .ZN (n_73));
  CKND1 g3137(.I (n_133), .ZN (n_69));
  NR2D1 g3138__1617(.A1 (BitCounter[0]), .A2 (BitCounter[1]), .ZN
       (n_68));
  CKND2D1 g3140__2802(.A1 (BitCounter[0]), .A2 (BitCounter[1]), .ZN
       (n_136));
  NR2D2 g3142__1705(.A1 (BitCounter[5]), .A2 (BitCounter[6]), .ZN
       (n_70));
  ND2D2 g3143__5122(.A1 (BitCounter[5]), .A2 (BitCounter[4]), .ZN
       (outctrl_n_49));
  ND2D1 g3144__8246(.A1 (BitCounter[5]), .A2 (InProgress), .ZN (n_133));
  CKND1 g3145(.I (WriteOp), .ZN (n_67));
  CKND1 g3150(.I (Reset), .ZN (n_4));
  SDFCNQD1 Nvalid_reg(.CDN (n_4), .CP (Clk), .D (Nvalid), .SI (n_139),
       .SE (n_22), .Q (Nvalid));
  DFCNQD1 RStatStart_reg(.CDN (n_4), .CP (Clk), .D (n_33), .Q
       (RStatStart));
  DFCNQD1 UpdateMIIRX_DATAReg_reg(.CDN (n_4), .CP (Clk), .D (n_0), .Q
       (UpdateMIIRX_DATAReg));
  SDFCNQD1 WCtrlDataStart_q_reg(.CDN (n_4), .CP (Clk), .D
       (WCtrlDataStart), .SI (WCtrlDataStart_q), .SE (EndBusy), .Q
       (WCtrlDataStart_q));
  DFCNQD1 WCtrlDataStart_reg(.CDN (n_4), .CP (Clk), .D (n_34), .Q
       (WCtrlDataStart));
  SDFCNQD2 WriteOp_reg(.CDN (n_4), .CP (Clk), .D (WriteOp), .SI (n_11),
       .SE (n_48), .Q (WriteOp));
  OAI21D1 g2595__7098(.A1 (n_58), .A2 (n_21), .B (n_60), .ZN (n_61));
  ND2D1 g2598__6131(.A1 (n_58), .A2 (n_21), .ZN (n_60));
  AO21D1 g2599__1881(.A1 (n_56), .A2 (n_19), .B (n_58), .Z (n_59));
  NR2XD1 g2601__5115(.A1 (n_56), .A2 (n_19), .ZN (n_58));
  OAI21D1 g2602__7482(.A1 (n_54), .A2 (n_20), .B (n_56), .ZN (n_57));
  CKND2D1 g2604__4733(.A1 (n_54), .A2 (n_20), .ZN (n_56));
  AO21D1 g2605__6161(.A1 (n_51), .A2 (n_24), .B (n_54), .Z (n_55));
  NR2XD1 g2607__9315(.A1 (n_51), .A2 (n_24), .ZN (n_54));
  OAI211D1 g2611__9945(.A1 (n_133), .A2 (n_36), .B (n_132), .C (n_49),
       .ZN (n_53));
  OAI21D1 g2612__2883(.A1 (n_50), .A2 (n_25), .B (n_51), .ZN (n_52));
  CKND2D1 g2614__2346(.A1 (n_50), .A2 (n_25), .ZN (n_51));
  IND3D1 g2617__1666(.A1 (BitCounter[5]), .B1 (InProgress), .B2 (n_36),
       .ZN (n_49));
  IOA21D1 g2618__7410(.A1 (n_44), .A2 (n_5), .B (n_43), .ZN (n_48));
  IAO21D2 g2619__6417(.A1 (n_42), .A2 (clkgen_n_104), .B
       (clkgen_Counter[0]), .ZN (n_50));
  INR2XD0 g2620__5477(.A1 (n_43), .B1 (n_44), .ZN (n_47));
  NR2XD0 g2621__2398(.A1 (n_39), .A2 (n_5), .ZN (n_46));
  OAI31D1 g2622__5107(.A1 (BitCounter[6]), .A2 (n_134), .A3 (n_1), .B
       (n_41), .ZN (n_45));
  INR2XD0 g2624__6260(.A1 (n_40), .B1 (n_182), .ZN (n_44));
  NR2XD0 g2625__4319(.A1 (n_38), .A2 (Divider[1]), .ZN (n_42));
  OAI211D1 g2626__8428(.A1 (outctrl_n_49), .A2 (n_1), .B (InProgress),
       .C (BitCounter[6]), .ZN (n_41));
  IND3D1 g2627__5526(.A1 (n_40), .B1 (BitCounter[3]), .B2 (n_15), .ZN
       (n_43));
  MAOI22D1 g2632__6783(.A1 (n_1), .A2 (BitCounter[4]), .B1 (n_1), .B2
       (BitCounter[4]), .ZN (n_39));
  INR3D0 g2633__3680(.A1 (n_30), .B1 (Divider[2]), .B2 (Divider[3]),
       .ZN (n_38));
  MOAI22D1 g2634__1617(.A1 (n_31), .A2 (shftrg_ShiftReg[1]), .B1
       (n_31), .B2 (LinkFail), .ZN (n_37));
  AO211D1 g2635__2802(.A1 (n_9), .A2 (RStatStart_q1), .B (n_29), .C
       (n_11), .Z (n_40));
  INR2XD0 g2636__1705(.A1 (BitCounter[4]), .B1 (n_1), .ZN (n_36));
  NR2XD0 g2639__5122(.A1 (n_13), .A2 (n_5), .ZN (n_35));
  MOAI22D1 g2640__8246(.A1 (n_26), .A2 (EndBusy), .B1 (WCtrlDataStart),
       .B2 (n_26), .ZN (n_34));
  MOAI22D1 g2641__7098(.A1 (n_27), .A2 (EndBusy), .B1 (RStatStart), .B2
       (n_27), .ZN (n_33));
  NR2XD0 g2642__6131(.A1 (n_18), .A2 (n_5), .ZN (n_32));
  NR4D1 g2645__1881(.A1 (Divider[5]), .A2 (Divider[4]), .A3
       (Divider[6]), .A4 (Divider[7]), .ZN (n_30));
  AN3XD1 g2646__5115(.A1 (n_5), .A2 (n_10), .A3 (SyncStatMdcEn), .Z
       (n_29));
  NR2XD0 g2647__7482(.A1 (n_14), .A2 (n_5), .ZN (n_28));
  IND3D1 g2648__4733(.A1 (n_181), .B1 (Rgad[0]), .B2 (n_17), .ZN
       (n_31));
  AOI21D1 g2649__6161(.A1 (n_6), .A2 (Divider[7]), .B
       (clkgen_Counter[6]), .ZN (n_23));
  AOI21D1 g2651__9315(.A1 (n_7), .A2 (RStat_q2), .B (EndBusy), .ZN
       (n_27));
  AOI21D1 g2652__9945(.A1 (n_8), .A2 (WCtrlData_q2), .B (EndBusy), .ZN
       (n_26));
  OAI21D1 g2653__2883(.A1 (n_130), .A2 (SyncStatMdcEn), .B (n_139), .ZN
       (n_22));
  AOI21D1 g2654__2346(.A1 (n_6), .A2 (Divider[2]), .B
       (clkgen_Counter[1]), .ZN (n_25));
  AO21D1 g2655__1666(.A1 (n_6), .A2 (Divider[3]), .B
       (clkgen_Counter[2]), .Z (n_24));
  XNR2D1 g2657__7410(.A1 (BitCounter[0]), .A2 (BitCounter[1]), .ZN
       (n_18));
  NR4D1 g2658__6417(.A1 (Rgad[1]), .A2 (Rgad[2]), .A3 (Rgad[3]), .A4
       (Rgad[4]), .ZN (n_17));
  MOAI22D1 g2659__5477(.A1 (clkgen_n_104), .A2 (Mdc), .B1
       (clkgen_n_104), .B2 (Mdc), .ZN (n_16));
  NR3D0 g2660__2398(.A1 (n_182), .A2 (n_137), .A3 (outctrl_n_49), .ZN
       (n_15));
  MAOI22D1 g2661__5107(.A1 (n_136), .A2 (BitCounter[2]), .B1 (n_136),
       .B2 (BitCounter[2]), .ZN (n_14));
  MAOI22D1 g2662__6260(.A1 (n_74), .A2 (BitCounter[3]), .B1 (n_74), .B2
       (BitCounter[3]), .ZN (n_13));
  AOI21D1 g2663__4319(.A1 (n_6), .A2 (Divider[6]), .B
       (clkgen_Counter[5]), .ZN (n_21));
  AOI21D1 g2664__8428(.A1 (n_6), .A2 (Divider[4]), .B
       (clkgen_Counter[3]), .ZN (n_20));
  AO21D1 g2665__5526(.A1 (n_6), .A2 (Divider[5]), .B
       (clkgen_Counter[4]), .Z (n_19));
  NR2XD0 g2666__6783(.A1 (n_5), .A2 (BitCounter[0]), .ZN (n_12));
  NR2XD0 g2668__3680(.A1 (InProgress_q1), .A2 (InProgress_q2), .ZN
       (n_10));
  INR2D1 g2669__1617(.A1 (WCtrlDataStart_q1), .B1 (WCtrlDataStart_q2),
       .ZN (n_11));
  INVD2 g2677(.I (clkgen_n_104), .ZN (n_6));
  INVD2 g2678(.I (InProgress), .ZN (n_5));
  BUFFD0 drc(.I (n_45), .Z (n_3));
  INR2D1 g2__2802(.A1 (n_60), .B1 (n_23), .ZN (n_2));
  IND2D2 g2683__1705(.A1 (n_74), .B1 (BitCounter[3]), .ZN (n_1));
  INR2D1 g2684__5122(.A1 (EndBusy), .B1 (WCtrlDataStart_q), .ZN (n_0));
  DFCND1 ScanStat_q2_reg(.CDN (n_4), .CP (Clk), .D (ScanStat_q1), .Q
       (ScanStat_q2), .QN (n_130));
  DFCND1 WCtrlData_q3_reg(.CDN (n_4), .CP (Clk), .D (WCtrlData_q2), .Q
       (WCtrlData_q3), .QN (n_8));
  DFCND1 RStat_q3_reg(.CDN (n_4), .CP (Clk), .D (RStat_q2), .Q
       (RStat_q3), .QN (n_7));
  CKND1 g3797(.I (n_499), .ZN (n_482));
  CKND0 g3798(.I (r_Bro), .ZN (n_481));
  DFCNQD1 DelayData_reg(.CDN (n_0), .CP (MRxClk), .D (StateData[0]), .Q
       (DelayData));
  DFCNQD1 RxEndFrm_d_reg(.CDN (n_0), .CP (MRxClk), .D (n_421), .Q
       (RxEndFrm_d));
  CKND2D1 g6970__8246(.A1 (n_480), .A2 (Crc[30]), .ZN (CrcError));
  NR3D0 g6971__7098(.A1 (n_479), .A2 (Crc[28]), .A3 (Crc[29]), .ZN
       (n_480));
  ND4D1 g6972__6131(.A1 (n_478), .A2 (Crc[31]), .A3 (Crc[26]), .A4
       (\crcrx_Crc[24]_360 ), .ZN (n_479));
  INR3D0 g6973__1881(.A1 (\crcrx_Crc[25]_361 ), .B1 (\crcrx_Crc[23]_359
       ), .B2 (n_477), .ZN (n_478));
  OR4D1 g6974__5115(.A1 (\crcrx_Crc[21]_357 ), .A2 (\crcrx_Crc[20]_356
       ), .A3 (\crcrx_Crc[19]_355 ), .A4 (n_475), .Z (n_477));
  OAI211D1 g6976__7482(.A1 (\crcrx_Crc[19]_355 ), .A2 (n_409), .B
       (n_474), .C (n_392), .ZN (n_476));
  CKND2D1 g6977__4733(.A1 (n_473), .A2 (\crcrx_Crc[18]_354 ), .ZN
       (n_475));
  ND2D1 g6978__6161(.A1 (n_409), .A2 (\crcrx_Crc[19]_355 ), .ZN
       (n_474));
  NR3D0 g6979__9315(.A1 (n_470), .A2 (\crcrx_Crc[22]_358 ), .A3
       (crcrx_CrcNext[21]), .ZN (n_473));
  IND2D1 g6983__9945(.A1 (crcrx_CrcNext[21]), .B1 (n_392), .ZN (n_472));
  IND2D1 g6984__2883(.A1 (crcrx_CrcNext[20]), .B1 (n_392), .ZN (n_471));
  IND4D1 g6985__2346(.A1 (crcrx_CrcNext[20]), .B1 (n_464), .B2
       (\crcrx_Crc[14]_352 ), .B3 (\crcrx_Crc[15]_353 ), .ZN (n_470));
  OAI211D1 g6986__1666(.A1 (\crcrx_Crc[15]_353 ), .A2 (n_491), .B
       (n_468), .C (n_392), .ZN (n_469));
  ND2D1 g6990__7410(.A1 (n_491), .A2 (\crcrx_Crc[15]_353 ), .ZN
       (n_468));
  OAI211D1 g6991__6417(.A1 (\crcrx_Crc[13]_351 ), .A2 (n_490), .B
       (n_463), .C (n_392), .ZN (n_467));
  OAI211D1 g6992__5477(.A1 (\crcrx_Crc[14]_352 ), .A2 (n_489), .B
       (n_461), .C (n_392), .ZN (n_466));
  OAI211D1 g6993__2398(.A1 (\crcrx_Crc[12]_350 ), .A2 (n_493), .B
       (n_462), .C (n_392), .ZN (n_465));
  NR2XD0 g6995__5107(.A1 (n_459), .A2 (\crcrx_Crc[13]_351 ), .ZN
       (n_464));
  ND2D1 g6996__6260(.A1 (n_490), .A2 (\crcrx_Crc[13]_351 ), .ZN
       (n_463));
  ND2D1 g6997__4319(.A1 (n_493), .A2 (\crcrx_Crc[12]_350 ), .ZN
       (n_462));
  ND2D1 g6998__8428(.A1 (n_489), .A2 (\crcrx_Crc[14]_352 ), .ZN
       (n_461));
  OAI211D1 g6999__5526(.A1 (\crcrx_Crc[11]_349 ), .A2 (n_491), .B
       (n_458), .C (n_392), .ZN (n_460));
  ND4D1 g7000__6783(.A1 (n_454), .A2 (\crcrx_Crc[10]_348 ), .A3
       (\crcrx_Crc[11]_349 ), .A4 (\crcrx_Crc[12]_350 ), .ZN (n_459));
  ND2D1 g7004__3680(.A1 (n_491), .A2 (\crcrx_Crc[11]_349 ), .ZN
       (n_458));
  OAI211D1 g7005__1617(.A1 (\crcrx_Crc[8]_346 ), .A2 (n_408), .B
       (n_453), .C (n_392), .ZN (n_457));
  OAI211D1 g7006__2802(.A1 (\crcrx_Crc[9]_347 ), .A2 (n_417), .B
       (n_452), .C (n_392), .ZN (n_456));
  OAI211D1 g7007__1705(.A1 (\crcrx_Crc[10]_348 ), .A2 (n_492), .B
       (n_451), .C (n_392), .ZN (n_455));
  NR2XD0 g7009__5122(.A1 (n_449), .A2 (\crcrx_Crc[9]_347 ), .ZN
       (n_454));
  ND2D1 g7010__8246(.A1 (n_408), .A2 (\crcrx_Crc[8]_346 ), .ZN (n_453));
  ND2D1 g7011__7098(.A1 (n_417), .A2 (\crcrx_Crc[9]_347 ), .ZN (n_452));
  ND2D1 g7012__6131(.A1 (n_492), .A2 (\crcrx_Crc[10]_348 ), .ZN
       (n_451));
  OAI211D1 g7013__1881(.A1 (\crcrx_Crc[7]_345 ), .A2 (n_414), .B
       (n_448), .C (n_392), .ZN (n_450));
  IND4D1 g7014__5115(.A1 (\crcrx_Crc[7]_345 ), .B1 (n_444), .B2
       (\crcrx_Crc[6]_344 ), .B3 (\crcrx_Crc[8]_346 ), .ZN (n_449));
  ND2D1 g7018__7482(.A1 (n_414), .A2 (\crcrx_Crc[7]_345 ), .ZN (n_448));
  OAI211D1 g7019__4733(.A1 (\crcrx_Crc[6]_344 ), .A2 (n_415), .B
       (n_441), .C (n_392), .ZN (n_447));
  ND2D1 g7020__6161(.A1 (n_443), .A2 (n_392), .ZN (n_446));
  OAI211D1 g7021__9315(.A1 (\crcrx_Crc[4]_342 ), .A2 (n_414), .B
       (n_442), .C (n_392), .ZN (n_445));
  AO21D1 g7022__9945(.A1 (n_436), .A2 (MRxDV), .B
       (rxcounters1_ResetByteCounter), .Z (rxcounters1_n_636));
  AN4XD1 g7024__2883(.A1 (n_426), .A2 (\crcrx_Crc[3]_341 ), .A3
       (\crcrx_Crc[4]_342 ), .A4 (\crcrx_Crc[5]_343 ), .Z (n_444));
  XNR2D1 g7025__2346(.A1 (n_416), .A2 (\crcrx_Crc[5]_343 ), .ZN
       (n_443));
  ND2D1 g7034__1666(.A1 (n_414), .A2 (\crcrx_Crc[4]_342 ), .ZN (n_442));
  ND2D1 g7035__7410(.A1 (n_415), .A2 (\crcrx_Crc[6]_344 ), .ZN (n_441));
  OAI211D1 g7036__6417(.A1 (\crcrx_Crc[3]_341 ), .A2 (n_415), .B
       (n_430), .C (n_392), .ZN (n_440));
  AN2XD1 g7037__5477(.A1 (GenerateRxValid), .A2 (LatchedByte[0]), .Z
       (n_439));
  AN2XD1 g7038__2398(.A1 (GenerateRxValid), .A2 (LatchedByte[1]), .Z
       (n_438));
  AN2XD1 g7039__5107(.A1 (GenerateRxValid), .A2 (LatchedByte[2]), .Z
       (n_437));
  OR4D1 g7043__6260(.A1 (StatePreamble), .A2 (StateSFD), .A3 (n_356),
       .A4 (n_418), .Z (n_436));
  AN2XD1 g7044__4319(.A1 (GenerateRxValid), .A2 (LatchedByte[4]), .Z
       (n_435));
  AN2XD1 g7045__8428(.A1 (GenerateRxValid), .A2 (LatchedByte[6]), .Z
       (n_434));
  AN2XD1 g7046__5526(.A1 (GenerateRxValid), .A2 (LatchedByte[7]), .Z
       (n_433));
  AN2XD1 g7048__6783(.A1 (GenerateRxValid), .A2 (LatchedByte[5]), .Z
       (n_432));
  AN2XD1 g7049__3680(.A1 (GenerateRxValid), .A2 (LatchedByte[3]), .Z
       (n_431));
  ND2D1 g7051__1617(.A1 (n_415), .A2 (\crcrx_Crc[3]_341 ), .ZN (n_430));
  OAI211D1 g7052__2802(.A1 (\crcrx_Crc[0]_338 ), .A2 (n_415), .B
       (n_423), .C (n_392), .ZN (n_429));
  AO21D2 g7053__1705(.A1 (n_419), .A2 (StateData[0]), .B (n_344), .Z
       (GenerateRxValid));
  OAI211D1 g7054__5122(.A1 (\crcrx_Crc[1]_339 ), .A2 (n_414), .B
       (n_422), .C (n_392), .ZN (n_428));
  ND2D1 g7055__8246(.A1 (n_424), .A2 (n_392), .ZN (n_427));
  NR2XD0 g7056__7098(.A1 (n_425), .A2 (\crcrx_Crc[2]_340 ), .ZN
       (n_426));
  IND3D1 g7059__6131(.A1 (Crc[27]), .B1 (\crcrx_Crc[0]_338 ), .B2
       (\crcrx_Crc[1]_339 ), .ZN (n_425));
  XNR2D1 g7060__1881(.A1 (n_416), .A2 (\crcrx_Crc[2]_340 ), .ZN
       (n_424));
  ND2D1 g7061__5115(.A1 (n_415), .A2 (\crcrx_Crc[0]_338 ), .ZN (n_423));
  ND2D1 g7062__7482(.A1 (n_414), .A2 (\crcrx_Crc[1]_339 ), .ZN (n_422));
  OA21D1 g7063__4733(.A1 (n_413), .A2 (ByteCntMaxFrame), .B
       (StateData[0]), .Z (n_421));
  ND2D1 g7064__6161(.A1 (n_417), .A2 (n_392), .ZN (n_420));
  IND3D1 g7065__9315(.A1 (DlyCrcCnt[2]), .B1 (n_347), .B2 (ByteCntEq0),
       .ZN (n_419));
  OA211D1 g7066__9945(.A1 (n_355), .A2 (rxcounters1_n_730), .B
       (rxcounters1_n_898), .C (StateData[1]), .Z (n_418));
  ND2D1 g7067__2883(.A1 (n_499), .A2 (n_1), .ZN (n_500));
  AO211D1 g7071__2346(.A1 (n_405), .A2 (n_369), .B (n_494), .C (n_407),
       .Z (n_417));
  OAI22D2 g7072__1666(.A1 (n_489), .A2 (n_368), .B1 (n_490), .B2
       (n_398), .ZN (n_416));
  OA22D2 g7073__7410(.A1 (n_492), .A2 (n_343), .B1 (n_493), .B2
       (n_404), .Z (n_415));
  OA22D2 g7074__6417(.A1 (n_409), .A2 (n_376), .B1 (n_491), .B2
       (n_385), .Z (n_414));
  INR2XD0 g7075__5477(.A1 (n_484), .B1 (MRxDV), .ZN (n_413));
  ND2D1 g7076__2398(.A1 (n_409), .A2 (n_392), .ZN (n_412));
  CKND2D1 g7077__5107(.A1 (ByteCntEq6), .A2 (StateData[0]), .ZN
       (n_499));
  OR3D1 g7078__6260(.A1 (n_352), .A2 (rxcounters1_n_756), .A3
       (rxcounters1_n_747), .Z (n_487));
  ND2D1 g7079__4319(.A1 (n_493), .A2 (n_392), .ZN (n_411));
  ND2D1 g7080__8428(.A1 (n_408), .A2 (n_392), .ZN (n_410));
  NR3D1 g7081__5526(.A1 (rxcounters1_n_747), .A2 (ByteCnt[1]), .A3
       (ByteCnt[0]), .ZN (ByteCntEq0));
  IND2D1 g7082__6783(.A1 (rxcounters1_n_747), .B1 (rxcounters1_n_894),
       .ZN (n_484));
  OR2XD1 g7083__3680(.A1 (n_494), .A2 (n_405), .Z (n_492));
  ND2D1 g7084__1617(.A1 (n_403), .A2 (n_385), .ZN (n_409));
  OR2D1 g7085__2802(.A1 (n_494), .A2 (n_397), .Z (n_489));
  OR2D1 g7086__1705(.A1 (n_494), .A2 (n_369), .Z (n_490));
  IND2D2 g7087__5122(.A1 (n_494), .B1 (n_376), .ZN (n_491));
  NR2D1 g7088__8246(.A1 (n_405), .A2 (n_369), .ZN (n_407));
  AO31D4 g7089__7098(.A1 (ByteCntMaxFrame), .A2 (MRxDV), .A3
       (StateData[0]), .B (n_389), .Z (rxcounters1_ResetByteCounter));
  NR2D1 g7090__6131(.A1 (n_402), .A2 (n_346), .ZN (ByteCntEq6));
  CKND2D1 g7091__1881(.A1 (n_406), .A2 (ByteCnt[13]), .ZN
       (rxcounters1_n_730));
  AO211D1 g7092__5115(.A1 (n_385), .A2 (n_398), .B (n_494), .C (n_401),
       .Z (n_408));
  ND2D2 g7093__7482(.A1 (n_403), .A2 (n_343), .ZN (n_493));
  INR2XD0 g7094__4733(.A1 (ByteCnt[14]), .B1 (rxcounters1_n_728), .ZN
       (n_406));
  OR2XD1 g7095__6161(.A1 (rxcounters1_n_746), .A2 (ByteCnt[2]), .Z
       (rxcounters1_n_747));
  CKND1 g7096(.I (n_405), .ZN (n_404));
  CKND1 g7097(.I (n_494), .ZN (n_403));
  OR2D1 g7098__9315(.A1 (rxcounters1_n_746), .A2 (rxcounters1_n_757),
       .Z (n_402));
  MUX2D1 g7099__9945(.I0 (n_397), .I1 (n_398), .S (n_376), .Z (n_405));
  AO211D2 g7100__2883(.A1 (n_70), .A2 (n_352), .B (ByteCntMaxFrame), .C
       (n_2), .Z (n_494));
  NR2D1 g7101__2346(.A1 (n_385), .A2 (n_398), .ZN (n_401));
  IND3D1 g7102__1666(.A1 (rxcounters1_n_726), .B1 (ByteCnt[12]), .B2
       (ByteCnt[11]), .ZN (rxcounters1_n_728));
  OR4D1 g7103__7410(.A1 (ByteCnt[6]), .A2 (ByteCnt[13]), .A3
       (ByteCnt[11]), .A4 (n_395), .Z (rxcounters1_n_746));
  AN4XD1 g7104__6417(.A1 (n_396), .A2 (n_381), .A3 (n_372), .A4
       (n_374), .Z (ByteCntMaxFrame));
  CKND1 g7105(.I (n_398), .ZN (n_397));
  CKXOR2D1 g7106__5477(.A1 (MRxD[1]), .A2 (Crc[30]), .Z (n_398));
  IND2D1 g7107__2398(.A1 (rxcounters1_n_725), .B1 (ByteCnt[10]), .ZN
       (rxcounters1_n_726));
  NR4D1 g7108__5107(.A1 (n_393), .A2 (n_383), .A3 (n_363), .A4 (HugEn),
       .ZN (n_396));
  OR4D1 g7110__6260(.A1 (ByteCnt[7]), .A2 (ByteCnt[5]), .A3
       (ByteCnt[4]), .A4 (n_391), .Z (n_395));
  IND2D1 g7111__4319(.A1 (rxcounters1_n_723), .B1 (ByteCnt[9]), .ZN
       (rxcounters1_n_725));
  IND2D1 g7112__8428(.A1 (Crc[26]), .B1 (n_392), .ZN (n_394));
  OAI211D1 g7113__5526(.A1 (ByteCnt[6]), .A2 (n_349), .B (n_341), .C
       (n_359), .ZN (n_393));
  IND2D1 g7114__6783(.A1 (rxcounters1_n_722), .B1 (ByteCnt[8]), .ZN
       (rxcounters1_n_723));
  IND2D1 g7115__3680(.A1 (rxcounters1_ResetIFGCounter), .B1 (n_340),
       .ZN (rxcounters1_n_638));
  INVD4 g7116(.I (Initialize_Crc), .ZN (n_392));
  IND2D1 g7117__1617(.A1 (rxcounters1_n_719), .B1 (ByteCnt[7]), .ZN
       (rxcounters1_n_722));
  AO21D2 g7118__2802(.A1 (n_382), .A2 (DlyCrcEn), .B (StateSFD), .Z
       (Initialize_Crc));
  OR2D1 g7119__1705(.A1 (n_389), .A2 (StateDrop), .Z
       (rxcounters1_ResetIFGCounter));
  IND2D1 g7120__5122(.A1 (rxcounters1_n_718), .B1 (ByteCnt[6]), .ZN
       (rxcounters1_n_719));
  OR4D1 g7121__8246(.A1 (ByteCnt[10]), .A2 (ByteCnt[8]), .A3
       (ByteCnt[9]), .A4 (n_380), .Z (n_391));
  AOI211XD0 g7122__7098(.A1 (n_349), .A2 (ByteCnt[6]), .B (n_384), .C
       (n_358), .ZN (n_390));
  IOA21D2 g7123__6131(.A1 (n_377), .A2 (n_347), .B (DlyCrcEn), .ZN
       (rxcounters1_n_898));
  IND2D1 g7124__1881(.A1 (rxcounters1_n_716), .B1 (ByteCnt[5]), .ZN
       (rxcounters1_n_718));
  OAI31D1 g7125__5115(.A1 (StatePreamble), .A2 (StateIdle), .A3
       (StateSFD), .B (n_387), .ZN (n_388));
  NR2XD0 g7126__7482(.A1 (n_2), .A2 (n_386), .ZN (n_389));
  CKND1 g7127(.I (n_387), .ZN (IFGCounterEq24));
  IND2D1 g7128__4733(.A1 (DlyCrcEn), .B1 (rxcounters1_n_213), .ZN
       (rxcounters1_n_641));
  IND2D1 g7129__6161(.A1 (n_497), .B1 (StateSFD), .ZN (n_386));
  IND2D1 g7130__9315(.A1 (rxcounters1_n_896), .B1 (ByteCnt[4]), .ZN
       (rxcounters1_n_716));
  NR2D1 g7131__9945(.A1 (n_379), .A2 (r_IFG), .ZN (n_387));
  ND4D1 g7132__2883(.A1 (n_361), .A2 (n_367), .A3 (n_366), .A4 (n_360),
       .ZN (n_384));
  ND4D1 g7133__2346(.A1 (n_364), .A2 (n_365), .A3 (n_362), .A4 (n_370),
       .ZN (n_383));
  MOAI22D1 g7134__1666(.A1 (n_377), .A2 (DlyCrcCnt[3]), .B1 (n_377),
       .B2 (DlyCrcCnt[3]), .ZN (n_382));
  MUX2D1 g7135__7410(.I0 (n_368), .I1 (n_369), .S (n_343), .Z (n_385));
  IND2D1 g7136__6417(.A1 (n_378), .B1 (MRxD[3]), .ZN (n_497));
  IND2D1 g7137__5477(.A1 (rxcounters1_n_895), .B1 (ByteCnt[3]), .ZN
       (rxcounters1_n_896));
  OR4D1 g7138__2398(.A1 (DlyCrcCnt[1]), .A2 (DlyCrcCnt[2]), .A3
       (n_348), .A4 (n_347), .Z (rxcounters1_n_213));
  NR2D1 g7139__5107(.A1 (n_375), .A2 (n_373), .ZN (n_381));
  OR4D1 g7140__6260(.A1 (ByteCnt[3]), .A2 (ByteCnt[15]), .A3
       (ByteCnt[14]), .A4 (ByteCnt[12]), .Z (n_380));
  AN3XD1 g7141__4319(.A1 (n_371), .A2 (rxcounters1_IFGCounter[4]), .A3
       (rxcounters1_IFGCounter[3]), .Z (n_379));
  MAOI22D1 g7143__8428(.A1 (MaxFL[3]), .A2 (ByteCnt[3]), .B1
       (MaxFL[3]), .B2 (ByteCnt[3]), .ZN (n_375));
  MUX2ND0 g7144__5526(.I0 (ByteCnt[0]), .I1 (n_345), .S (MaxFL[0]), .ZN
       (n_374));
  MUX2ND0 g7145__6783(.I0 (n_353), .I1 (ByteCnt[1]), .S (MaxFL[1]), .ZN
       (n_373));
  MAOI22D1 g7146__3680(.A1 (n_346), .A2 (MaxFL[2]), .B1 (n_346), .B2
       (MaxFL[2]), .ZN (n_372));
  NR3D0 g7147__1617(.A1 (rxcounters1_IFGCounter[2]), .A2
       (rxcounters1_IFGCounter[1]), .A3 (rxcounters1_IFGCounter[0]),
       .ZN (n_371));
  MOAI22D1 g7148__2802(.A1 (ByteCnt[15]), .A2 (MaxFL[15]), .B1
       (ByteCnt[15]), .B2 (MaxFL[15]), .ZN (n_370));
  ND3D2 g7149__1705(.A1 (StateData[0]), .A2 (DlyCrcCnt[0]), .A3
       (DlyCrcCnt[1]), .ZN (n_486));
  OR2D1 g7150__5122(.A1 (rxcounters1_n_894), .A2 (n_346), .Z
       (rxcounters1_n_895));
  IND3D1 g7151__8246(.A1 (MRxD[1]), .B1 (MRxD[2]), .B2 (MRxD[0]), .ZN
       (n_378));
  NR3D1 g7152__7098(.A1 (DlyCrcCnt[2]), .A2 (DlyCrcCnt[0]), .A3
       (DlyCrcCnt[1]), .ZN (n_377));
  XOR2D1 g7153__6131(.A1 (MRxD[0]), .A2 (Crc[31]), .Z (n_376));
  CKND1 g7154(.I (n_369), .ZN (n_368));
  XNR2D1 g7155__1881(.A1 (MaxFL[11]), .A2 (ByteCnt[11]), .ZN (n_367));
  XNR2D1 g7156__5115(.A1 (MaxFL[9]), .A2 (ByteCnt[9]), .ZN (n_366));
  XNR2D1 g7157__7482(.A1 (MaxFL[13]), .A2 (ByteCnt[13]), .ZN (n_365));
  XNR2D1 g7158__4733(.A1 (MaxFL[12]), .A2 (ByteCnt[12]), .ZN (n_364));
  XOR2D1 g7159__6161(.A1 (MaxFL[5]), .A2 (ByteCnt[5]), .Z (n_363));
  XNR2D1 g7160__9315(.A1 (MaxFL[14]), .A2 (ByteCnt[14]), .ZN (n_362));
  XNR2D1 g7161__9945(.A1 (MaxFL[8]), .A2 (ByteCnt[8]), .ZN (n_361));
  XNR2D1 g7162__2883(.A1 (MaxFL[10]), .A2 (ByteCnt[10]), .ZN (n_360));
  XNR2D1 g7163__2346(.A1 (MaxFL[4]), .A2 (ByteCnt[4]), .ZN (n_359));
  CKXOR2D1 g7164__1666(.A1 (ByteCnt[7]), .A2 (MaxFL[7]), .Z (n_358));
  XOR2D1 g7165__7410(.A1 (MRxD[3]), .A2 (Crc[28]), .Z (n_343));
  XNR2D1 g7166__6417(.A1 (MRxD[2]), .A2 (Crc[29]), .ZN (n_369));
  NR2D3 g7169__5477(.A1 (Reset), .A2 (StateIdle), .ZN (n_1));
  OR2D1 g7170__2398(.A1 (n_345), .A2 (n_353), .Z (rxcounters1_n_894));
  INR2XD0 g7171__5107(.A1 (StateIdle), .B1 (Transmitting), .ZN (n_356));
  CKND2D1 g7172__6260(.A1 (n_353), .A2 (ByteCnt[0]), .ZN
       (rxcounters1_n_756));
  CKND2D1 g7173__4319(.A1 (n_345), .A2 (ByteCnt[1]), .ZN
       (rxcounters1_n_757));
  CKND1 g7174(.I (ByteCnt[15]), .ZN (n_355));
  CKND1 g7175(.I (MRxDV), .ZN (n_2));
  CKND1 g7176(.I (ByteCnt[1]), .ZN (n_353));
  CKND1 g7177(.I (StateData[0]), .ZN (n_352));
  INVD1 g7178(.I (Reset), .ZN (n_0));
  CKND1 g7180(.I (MaxFL[6]), .ZN (n_349));
  CKND1 g7181(.I (DlyCrcCnt[0]), .ZN (n_348));
  CKND1 g7182(.I (DlyCrcCnt[3]), .ZN (n_347));
  CKND1 g7183(.I (ByteCnt[2]), .ZN (n_346));
  CKND1 g7184(.I (ByteCnt[0]), .ZN (n_345));
  INVD1 drc_bufs7186(.I (n_486), .ZN (n_344));
  BUFFD0 drc(.I (n_388), .Z (n_340));
  BUFFD0 drc7227(.I (n_390), .Z (n_341));
  IND2D1 g2__8428(.A1 (GenerateRxValid), .B1 (DelayData), .ZN (n_502));
  DFCNQD1 Broadcast_reg(.CDN (n_0), .CP (MRxClk), .D (n_648), .Q
       (Broadcast));
  SDFCNQD1 Multicast_reg(.CDN (n_0), .CP (MRxClk), .D (Multicast), .SI
       (n_96), .SE (n_155), .Q (Multicast));
  DFCNQD1 RxStartFrm_reg(.CDN (n_0), .CP (MRxClk), .D (RxStartFrm_d),
       .Q (RxStartFrm));
  DFCNQD2 RxValid_reg(.CDN (n_0), .CP (MRxClk), .D (RxValid_d), .Q
       (RxValid));
  SDFCNQD1 rxaddrcheck1_AddressMiss_reg(.CDN (n_0), .CP (MRxClk), .D
       (n_245), .SI (AddressMiss), .SE (n_58), .Q (AddressMiss));
  DFCNQD1 rxaddrcheck1_MulticastOK_reg(.CDN (n_0), .CP (MRxClk), .D
       (n_339), .Q (rxaddrcheck1_MulticastOK));
  DFCNQD1 rxaddrcheck1_RxAbort_reg(.CDN (n_0), .CP (MRxClk), .D
       (n_270), .Q (RxAbort));
  SDFCNQD2 rxaddrcheck1_UnicastOK_reg(.CDN (n_0), .CP (MRxClk), .D
       (rxaddrcheck1_UnicastOK), .SI (n_338), .SE (n_308), .Q
       (rxaddrcheck1_UnicastOK));
  SDFCNQD4 rxstatem1_StateData0_reg(.CDN (n_0), .CP (MRxClk), .D
       (n_304), .SI (StateData[0]), .SE (n_317), .Q (StateData[0]));
  SDFCNQD2 rxstatem1_StateData1_reg(.CDN (n_0), .CP (MRxClk), .D
       (n_301), .SI (StateData[1]), .SE (n_317), .Q (StateData[1]));
  SDFSNQD1 rxstatem1_StateDrop_reg(.SDN (n_0), .CP (MRxClk), .D
       (StateDrop), .SI (n_257), .SE (n_42), .Q (StateDrop));
  DFCNQD2 rxstatem1_StateIdle_reg(.CDN (n_0), .CP (MRxClk), .D (n_321),
       .Q (StateIdle));
  SDFCNQD2 rxstatem1_StateSFD_reg(.CDN (n_0), .CP (MRxClk), .D
       (StateSFD), .SI (n_312), .SE (n_315), .Q (StateSFD));
  INR2XD0 g8042__5526(.A1 (n_86), .B1 (n_337), .ZN (n_339));
  OAI211D1 g8043__6783(.A1 (n_310), .A2 (n_187), .B (n_335), .C
       (n_325), .ZN (n_338));
  MUX2ND0 g8044__3680(.I0 (n_336), .I1 (rxaddrcheck1_MulticastOK), .S
       (n_98), .ZN (n_337));
  IND4D1 g8047__1617(.A1 (n_300), .B1 (n_332), .B2 (n_293), .B3 (n_28),
       .ZN (n_336));
  AOI32D1 g8048__2802(.A1 (n_259), .A2 (n_33), .A3
       (rxaddrcheck1_UnicastOK), .B1 (n_331), .B2
       (rxaddrcheck1_UnicastOK), .ZN (n_335));
  INR2XD0 g8049__1705(.A1 (rxcounters1_n_213), .B1 (n_329), .ZN
       (n_334));
  NR2XD0 g8050__5122(.A1 (n_330), .A2 (rxcounters1_ResetIFGCounter),
       .ZN (n_333));
  OA221D0 g8055__8246(.A1 (n_275), .A2 (n_181), .B1 (n_185), .B2
       (n_274), .C (n_327), .Z (n_332));
  MOAI22D1 g8056__7098(.A1 (n_23), .A2 (n_309), .B1 (n_212), .B2
       (n_320), .ZN (n_331));
  MAOI22D1 g8057__6131(.A1 (n_307), .A2 (rxcounters1_IFGCounter[4]),
       .B1 (n_307), .B2 (rxcounters1_IFGCounter[4]), .ZN (n_330));
  AOI32D1 g8058__1881(.A1 (n_314), .A2 (n_68), .A3 (n_87), .B1
       (rxcounters1_n_898), .B2 (DlyCrcCnt[3]), .ZN (n_329));
  NR3D0 g8064__5115(.A1 (n_324), .A2 (n_299), .A3 (n_305), .ZN (n_327));
  OA211D1 g8065__7482(.A1 (rxcounters1_IFGCounter[3]), .A2 (n_255), .B
       (n_76), .C (n_307), .Z (n_326));
  AOI33D1 g8066__4733(.A1 (n_260), .A2 (n_31), .A3
       (rxaddrcheck1_UnicastOK), .B1 (n_188), .B2 (n_34), .B3
       (rxaddrcheck1_UnicastOK), .ZN (n_325));
  OAI221D1 g8067__6161(.A1 (n_224), .A2 (n_178), .B1 (n_179), .B2
       (n_225), .C (n_25), .ZN (n_324));
  AOI211XD0 g8068__9315(.A1 (n_62), .A2 (MAC[31]), .B (n_294), .C
       (n_252), .ZN (n_323));
  OAI31D1 g8070__9945(.A1 (n_191), .A2 (n_42), .A3 (n_306), .B (n_316),
       .ZN (n_322));
  MOAI22D1 g8071__2883(.A1 (n_306), .A2 (n_289), .B1 (n_306), .B2
       (StateIdle), .ZN (n_321));
  NR3D0 g8072__2346(.A1 (n_311), .A2 (n_130), .A3 (n_119), .ZN (n_320));
  AO32D1 g8073__1666(.A1 (n_68), .A2 (n_261), .A3 (n_87), .B1
       (rxcounters1_n_898), .B2 (DlyCrcCnt[2]), .Z (n_319));
  CKND2D1 g8074__7410(.A1 (n_306), .A2 (StatePreamble), .ZN (n_316));
  ND2D1 g8076__6417(.A1 (n_301), .A2 (n_256), .ZN (n_315));
  INR2XD0 g8078__5477(.A1 (n_301), .B1 (StateData[0]), .ZN (n_317));
  MOAI22D1 g8080__2398(.A1 (n_258), .A2 (DlyCrcCnt[3]), .B1 (n_258),
       .B2 (DlyCrcCnt[3]), .ZN (n_314));
  AOI211XD0 g8081__5107(.A1 (n_222), .A2 (n_183), .B (n_298), .C
       (n_277), .ZN (n_313));
  OA21D1 g8082__6260(.A1 (n_108), .A2 (n_91), .B (n_301), .Z (n_312));
  OAI211D1 g8083__4319(.A1 (MAC[7]), .A2 (n_62), .B (n_287), .C
       (n_165), .ZN (n_311));
  OAI211D1 g8084__8428(.A1 (MAC[46]), .A2 (n_74), .B (n_281), .C
       (n_32), .ZN (n_310));
  OAI211D1 g8085__5526(.A1 (MAC[15]), .A2 (n_62), .B (n_284), .C
       (n_105), .ZN (n_309));
  IND4D1 g8086__6783(.A1 (n_259), .B1 (n_264), .B2 (n_58), .B3 (n_86),
       .ZN (n_308));
  OAI221D1 g8087__3680(.A1 (n_215), .A2 (n_41), .B1 (n_179), .B2
       (n_216), .C (n_285), .ZN (n_305));
  NR2XD0 g8089__1617(.A1 (n_292), .A2 (StateData[0]), .ZN (n_304));
  INR2XD0 g8090__2802(.A1 (rxcounters1_n_213), .B1 (n_283), .ZN
       (n_303));
  CKND2D1 g8092__1705(.A1 (n_255), .A2 (rxcounters1_IFGCounter[3]), .ZN
       (n_307));
  AN2XD1 g8095__5122(.A1 (n_59), .A2 (n_256), .Z (n_306));
  OAI221D1 g8096__8246(.A1 (n_233), .A2 (n_185), .B1 (n_181), .B2
       (n_234), .C (n_282), .ZN (n_300));
  OAI221D1 g8097__7098(.A1 (n_219), .A2 (n_39), .B1 (n_41), .B2
       (n_240), .C (n_280), .ZN (n_299));
  MOAI22D1 g8098__6131(.A1 (n_276), .A2 (n_184), .B1 (n_265), .B2
       (n_183), .ZN (n_298));
  AOI211XD0 g8099__1881(.A1 (n_64), .A2 (MAC[34]), .B (n_269), .C
       (n_253), .ZN (n_297));
  AOI211XD0 g8100__5115(.A1 (n_235), .A2 (n_180), .B (n_278), .C
       (n_273), .ZN (n_296));
  AOI211XD0 g8101__7482(.A1 (n_107), .A2 (n_56), .B
       (rxcounters1_ResetIFGCounter), .C (n_255), .ZN (n_295));
  OAI211D1 g8102__4733(.A1 (MAC[27]), .A2 (n_65), .B (n_35), .C
       (n_127), .ZN (n_294));
  AOI211XD0 g8103__6161(.A1 (n_213), .A2 (n_180), .B (n_279), .C
       (n_272), .ZN (n_293));
  OA211D1 g8105__9315(.A1 (n_69), .A2 (n_497), .B (n_59), .C (n_70), .Z
       (n_301));
  NR2XD0 g8107__9945(.A1 (n_263), .A2 (rxcounters1_ResetByteCounter),
       .ZN (n_291));
  AOI211XD0 g8108__2883(.A1 (n_66), .A2 (MAC[16]), .B (n_268), .C
       (n_249), .ZN (n_290));
  CKND2D1 g8109__2346(.A1 (n_271), .A2 (n_256), .ZN (n_289));
  AO211D1 g8110__1666(.A1 (n_199), .A2 (\crcrx_Crc[22]_358 ), .B
       (n_244), .C (Initialize_Crc), .Z (n_288));
  AN4XD1 g8111__7410(.A1 (n_189), .A2 (n_163), .A3 (n_118), .A4
       (n_117), .Z (n_287));
  NR2XD0 g8112__6417(.A1 (n_262), .A2 (rxcounters1_ResetByteCounter),
       .ZN (n_286));
  CKND2D1 g8114__5477(.A1 (n_271), .A2 (n_257), .ZN (n_292));
  OA22D0 g8115__2398(.A1 (n_242), .A2 (n_39), .B1 (n_178), .B2 (n_214),
       .Z (n_285));
  AN4XD1 g8116__5107(.A1 (n_250), .A2 (n_123), .A3 (n_124), .A4
       (n_125), .Z (n_284));
  AOI32D1 g8117__6260(.A1 (n_68), .A2 (n_24), .A3 (n_87), .B1
       (rxcounters1_n_898), .B2 (DlyCrcCnt[1]), .ZN (n_283));
  OA22D0 g8118__4319(.A1 (n_231), .A2 (n_181), .B1 (n_185), .B2
       (n_232), .Z (n_282));
  AN4XD1 g8119__8428(.A1 (n_251), .A2 (n_135), .A3 (n_134), .A4
       (n_153), .Z (n_281));
  MAOI22D1 g8120__5526(.A1 (n_218), .A2 (n_183), .B1 (n_217), .B2
       (n_184), .ZN (n_280));
  MOAI22D1 g8121__6783(.A1 (n_241), .A2 (n_27), .B1 (n_239), .B2
       (n_180), .ZN (n_279));
  MOAI22D1 g8122__3680(.A1 (n_238), .A2 (n_177), .B1 (n_237), .B2
       (n_180), .ZN (n_278));
  NR2D1 g8123__1617(.A1 (n_223), .A2 (n_184), .ZN (n_277));
  AN2XD1 g8124__2802(.A1 (n_220), .A2 (n_221), .Z (n_276));
  AN2XD1 g8125__1705(.A1 (n_227), .A2 (n_226), .Z (n_275));
  AN2XD1 g8126__5122(.A1 (n_228), .A2 (n_230), .Z (n_274));
  NR2D1 g8127__8246(.A1 (n_236), .A2 (n_27), .ZN (n_273));
  NR2D1 g8128__7098(.A1 (n_254), .A2 (n_177), .ZN (n_272));
  INR3D0 g8134__6131(.A1 (n_200), .B1 (r_Pro), .B2 (n_58), .ZN (n_270));
  ND4D1 g8135__1881(.A1 (n_30), .A2 (n_147), .A3 (n_145), .A4 (n_144),
       .ZN (n_269));
  OAI211D1 g8136__5115(.A1 (MAC[16]), .A2 (n_66), .B (n_36), .C
       (n_143), .ZN (n_268));
  AOI31D1 g8137__7482(.A1 (n_148), .A2 (n_156), .A3 (LatchedByte[0]),
       .B (rxcounters1_n_746), .ZN (n_267));
  AOI211XD0 g8138__4733(.A1 (n_65), .A2 (MAC[27]), .B (n_246), .C
       (n_84), .ZN (n_266));
  AO221D0 g8139__6161(.A1 (n_176), .A2 (r_HASH0[11]), .B1 (n_172), .B2
       (r_HASH1[11]), .C (n_229), .Z (n_265));
  INR3D0 g8140__9315(.A1 (n_187), .B1 (n_260), .B2 (n_209), .ZN
       (n_264));
  MAOI22D1 g8141__9945(.A1 (n_92), .A2 (ByteCnt[12]), .B1 (n_92), .B2
       (ByteCnt[12]), .ZN (n_263));
  MAOI22D1 g8142__2883(.A1 (n_89), .A2 (ByteCnt[14]), .B1 (n_89), .B2
       (ByteCnt[14]), .ZN (n_262));
  MOAI22D1 g8143__2346(.A1 (n_88), .A2 (DlyCrcCnt[2]), .B1 (n_88), .B2
       (DlyCrcCnt[2]), .ZN (n_261));
  AOI22D1 g8144__1666(.A1 (n_197), .A2 (MRxDV), .B1 (n_90), .B2
       (Transmitting), .ZN (n_271));
  AOI22D1 g8145__7410(.A1 (n_176), .A2 (r_HASH0[31]), .B1 (n_172), .B2
       (r_HASH1[31]), .ZN (n_254));
  OAI211D1 g8148__6417(.A1 (MAC[34]), .A2 (n_64), .B (n_115), .C
       (n_116), .ZN (n_253));
  OAI211D1 g8149__5477(.A1 (MAC[31]), .A2 (n_62), .B (n_129), .C
       (n_128), .ZN (n_252));
  AOI211XD0 g8150__2398(.A1 (n_74), .A2 (MAC[46]), .B (n_132), .C
       (n_131), .ZN (n_251));
  AN4XD1 g8151__5107(.A1 (n_122), .A2 (n_120), .A3 (n_121), .A4
       (n_664), .Z (n_250));
  ND4D1 g8152__6260(.A1 (n_141), .A2 (n_140), .A3 (n_139), .A4 (n_137),
       .ZN (n_249));
  OA211D1 g8153__4319(.A1 (ByteCnt[13]), .A2 (n_71), .B (n_89), .C
       (n_73), .Z (n_248));
  OA211D1 g8154__8428(.A1 (ByteCnt[11]), .A2 (n_77), .B (n_92), .C
       (n_73), .Z (n_247));
  OAI211D1 g8155__5526(.A1 (MAC[30]), .A2 (n_74), .B (n_190), .C
       (n_99), .ZN (n_246));
  AOI21D1 g8156__6783(.A1 (PassAll), .A2 (ControlFrmAddressOK), .B
       (n_201), .ZN (n_245));
  NR2XD0 g8157__3680(.A1 (n_199), .A2 (\crcrx_Crc[22]_358 ), .ZN
       (n_244));
  OA211D1 g8158__1617(.A1 (rxcounters1_IFGCounter[1]), .A2
       (rxcounters1_IFGCounter[0]), .B (n_76), .C (n_107), .Z (n_243));
  AN3XD1 g8159__2802(.A1 (n_182), .A2 (n_72), .A3 (ByteCnt[2]), .Z
       (n_260));
  AN3XD1 g8160__1705(.A1 (n_182), .A2 (n_79), .A3 (ByteCnt[2]), .Z
       (n_259));
  IND2D1 g8161__5122(.A1 (n_88), .B1 (DlyCrcCnt[2]), .ZN (n_258));
  AO31D1 g8162__8246(.A1 (n_106), .A2 (n_83), .A3 (n_69), .B (MRxDV),
       .Z (n_257));
  OA21D1 g8163__7098(.A1 (n_186), .A2 (n_55), .B (n_91), .Z (n_256));
  NR2XD1 g8166__6131(.A1 (n_107), .A2 (n_56), .ZN (n_255));
  AOI22D1 g8175__1881(.A1 (n_169), .A2 (r_HASH0[0]), .B1 (n_170), .B2
       (r_HASH1[0]), .ZN (n_242));
  AOI22D1 g8176__5115(.A1 (n_173), .A2 (r_HASH0[23]), .B1 (n_174), .B2
       (r_HASH1[23]), .ZN (n_241));
  AOI22D1 g8177__7482(.A1 (n_176), .A2 (r_HASH0[25]), .B1 (n_172), .B2
       (r_HASH1[25]), .ZN (n_240));
  AO22D0 g8178__4733(.A1 (n_173), .A2 (r_HASH0[7]), .B1 (r_HASH1[7]),
       .B2 (n_174), .Z (n_239));
  AOI22D1 g8179__6161(.A1 (n_171), .A2 (r_HASH0[30]), .B1 (n_175), .B2
       (r_HASH1[30]), .ZN (n_238));
  AO22D0 g8180__9315(.A1 (n_171), .A2 (r_HASH0[14]), .B1 (r_HASH1[14]),
       .B2 (n_175), .Z (n_237));
  AOI22D1 g8181__9945(.A1 (n_169), .A2 (r_HASH0[22]), .B1 (n_170), .B2
       (r_HASH1[22]), .ZN (n_236));
  AO22D0 g8182__2883(.A1 (n_169), .A2 (r_HASH0[6]), .B1 (r_HASH1[6]),
       .B2 (n_170), .Z (n_235));
  AOI22D1 g8183__2346(.A1 (n_171), .A2 (r_HASH0[12]), .B1 (n_175), .B2
       (r_HASH1[12]), .ZN (n_234));
  AOI22D1 g8184__1666(.A1 (n_169), .A2 (r_HASH0[20]), .B1 (n_170), .B2
       (r_HASH1[20]), .ZN (n_233));
  AOI22D1 g8185__7410(.A1 (n_171), .A2 (r_HASH0[28]), .B1 (n_175), .B2
       (r_HASH1[28]), .ZN (n_232));
  AOI22D1 g8186__6417(.A1 (n_169), .A2 (r_HASH0[4]), .B1 (n_170), .B2
       (r_HASH1[4]), .ZN (n_231));
  AOI22D1 g8187__5477(.A1 (n_176), .A2 (r_HASH0[29]), .B1 (n_172), .B2
       (r_HASH1[29]), .ZN (n_230));
  AO22D0 g8188__2398(.A1 (n_173), .A2 (r_HASH0[3]), .B1 (r_HASH1[3]),
       .B2 (n_174), .Z (n_229));
  AOI22D1 g8189__5107(.A1 (n_173), .A2 (r_HASH0[21]), .B1 (n_174), .B2
       (r_HASH1[21]), .ZN (n_228));
  AOI22D1 g8190__6260(.A1 (n_173), .A2 (r_HASH0[5]), .B1 (n_174), .B2
       (r_HASH1[5]), .ZN (n_227));
  AOI22D1 g8191__4319(.A1 (n_176), .A2 (r_HASH0[13]), .B1 (n_172), .B2
       (r_HASH1[13]), .ZN (n_226));
  AOI22D1 g8192__8428(.A1 (n_171), .A2 (r_HASH0[8]), .B1 (n_175), .B2
       (r_HASH1[8]), .ZN (n_225));
  AOI22D1 g8193__5526(.A1 (n_169), .A2 (r_HASH0[16]), .B1 (n_170), .B2
       (r_HASH1[16]), .ZN (n_224));
  AOI22D1 g8194__6783(.A1 (n_171), .A2 (r_HASH0[26]), .B1 (n_175), .B2
       (r_HASH1[26]), .ZN (n_223));
  AO22D0 g8195__3680(.A1 (n_169), .A2 (r_HASH0[2]), .B1 (r_HASH1[2]),
       .B2 (n_170), .Z (n_222));
  AOI22D1 g8196__1617(.A1 (n_176), .A2 (r_HASH0[27]), .B1 (n_172), .B2
       (r_HASH1[27]), .ZN (n_221));
  AOI22D1 g8197__2802(.A1 (n_173), .A2 (r_HASH0[19]), .B1 (n_174), .B2
       (r_HASH1[19]), .ZN (n_220));
  AOI22D1 g8198__1705(.A1 (n_173), .A2 (r_HASH0[1]), .B1 (n_174), .B2
       (r_HASH1[1]), .ZN (n_219));
  AO22D0 g8199__5122(.A1 (n_171), .A2 (r_HASH0[10]), .B1 (r_HASH1[10]),
       .B2 (n_175), .Z (n_218));
  AOI22D1 g8200__8246(.A1 (n_169), .A2 (r_HASH0[18]), .B1 (n_170), .B2
       (r_HASH1[18]), .ZN (n_217));
  AOI22D1 g8201__7098(.A1 (n_176), .A2 (r_HASH0[9]), .B1 (n_172), .B2
       (r_HASH1[9]), .ZN (n_216));
  AOI22D1 g8202__6131(.A1 (n_173), .A2 (r_HASH0[17]), .B1 (n_174), .B2
       (r_HASH1[17]), .ZN (n_215));
  AOI22D1 g8203__1881(.A1 (n_171), .A2 (r_HASH0[24]), .B1 (n_175), .B2
       (r_HASH1[24]), .ZN (n_214));
  AO22D0 g8204__5115(.A1 (n_176), .A2 (r_HASH0[15]), .B1 (r_HASH1[15]),
       .B2 (n_172), .Z (n_213));
  NR2XD0 g8206__7482(.A1 (rxcounters1_ResetByteCounter), .A2 (n_150),
       .ZN (n_211));
  NR2XD0 g8207__4733(.A1 (rxcounters1_ResetByteCounter), .A2 (n_160),
       .ZN (n_210));
  IND2D1 g8208__6161(.A1 (n_188), .B1 (n_23), .ZN (n_209));
  NR2XD0 g8209__9315(.A1 (rxcounters1_ResetByteCounter), .A2 (n_164),
       .ZN (n_208));
  NR2XD0 g8210__9945(.A1 (rxcounters1_ResetByteCounter), .A2 (n_166),
       .ZN (n_207));
  NR2XD0 g8211__2883(.A1 (rxcounters1_ResetByteCounter), .A2 (n_159),
       .ZN (n_206));
  NR2XD0 g8212__2346(.A1 (n_152), .A2 (rxcounters1_ResetByteCounter),
       .ZN (n_205));
  NR2XD0 g8213__1666(.A1 (rxcounters1_ResetByteCounter), .A2 (n_168),
       .ZN (n_204));
  NR2XD0 g8214__7410(.A1 (rxcounters1_ResetByteCounter), .A2 (n_133),
       .ZN (n_203));
  NR2XD0 g8215__6417(.A1 (rxcounters1_ResetByteCounter), .A2 (n_149),
       .ZN (n_202));
  INR2D1 g8217__5477(.A1 (n_182), .B1 (rxcounters1_n_895), .ZN (n_212));
  CKND1 g8218(.I (n_200), .ZN (n_201));
  AOI211XD0 g8219__2398(.A1 (n_62), .A2 (MAC[47]), .B (n_136), .C
       (n_82), .ZN (n_198));
  OAI31D2 g8220__5107(.A1 (n_69), .A2 (IFGCounterEq24), .A3 (n_497), .B
       (n_81), .ZN (n_197));
  AO211D1 g8221__6260(.A1 (n_489), .A2 (\crcrx_Crc[24]_360 ), .B
       (n_103), .C (Initialize_Crc), .Z (n_196));
  AO211D1 g8222__4319(.A1 (n_491), .A2 (\crcrx_Crc[25]_361 ), .B
       (n_102), .C (Initialize_Crc), .Z (n_195));
  AOI211XD0 g8223__8428(.A1 (n_65), .A2 (MAC[35]), .B (n_146), .C
       (n_104), .ZN (n_194));
  AOI211XD0 g8224__5526(.A1 (n_64), .A2 (MAC[18]), .B (n_142), .C
       (n_101), .ZN (n_193));
  NR2XD0 g8225__6783(.A1 (rxcounters1_ResetByteCounter), .A2 (n_167),
       .ZN (n_192));
  IAO21D1 g8226__3680(.A1 (StateIdle), .A2 (StatePreamble), .B (n_186),
       .ZN (n_191));
  AOI21D1 g8227__1617(.A1 (n_49), .A2 (MAC[29]), .B (n_660), .ZN
       (n_190));
  AOI21D1 g8228__2802(.A1 (n_74), .A2 (MAC[6]), .B (n_138), .ZN
       (n_189));
  NR2XD0 g8229__1705(.A1 (n_158), .A2 (rxaddrcheck1_UnicastOK), .ZN
       (n_200));
  AO211D1 g8230__5122(.A1 (n_376), .A2 (n_343), .B (n_494), .C (n_85),
       .Z (n_199));
  MAOI22D1 g8231__8246(.A1 (rxcounters1_n_719), .A2 (ByteCnt[7]), .B1
       (rxcounters1_n_719), .B2 (ByteCnt[7]), .ZN (n_168));
  MAOI22D1 g8232__7098(.A1 (rxcounters1_n_716), .A2 (ByteCnt[5]), .B1
       (rxcounters1_n_716), .B2 (ByteCnt[5]), .ZN (n_167));
  MAOI22D1 g8233__6131(.A1 (rxcounters1_n_895), .A2 (ByteCnt[3]), .B1
       (rxcounters1_n_895), .B2 (ByteCnt[3]), .ZN (n_166));
  MOAI22D1 g8234__1881(.A1 (n_54), .A2 (MAC[1]), .B1 (n_54), .B2
       (MAC[1]), .ZN (n_165));
  MAOI22D1 g8235__5115(.A1 (rxcounters1_n_894), .A2 (ByteCnt[2]), .B1
       (rxcounters1_n_894), .B2 (ByteCnt[2]), .ZN (n_164));
  MAOI22D1 g8236__7482(.A1 (n_62), .A2 (MAC[7]), .B1 (n_74), .B2
       (MAC[6]), .ZN (n_163));
  CKND2D1 g8238__4733(.A1 (n_86), .A2 (Broadcast), .ZN (n_161));
  MAOI22D1 g8239__6161(.A1 (rxcounters1_n_722), .A2 (ByteCnt[8]), .B1
       (rxcounters1_n_722), .B2 (ByteCnt[8]), .ZN (n_160));
  MAOI22D1 g8240__9315(.A1 (rxcounters1_n_896), .A2 (ByteCnt[4]), .B1
       (rxcounters1_n_896), .B2 (ByteCnt[4]), .ZN (n_159));
  AO21D1 g8242__9945(.A1 (Broadcast), .A2 (n_481), .B
       (rxaddrcheck1_MulticastOK), .Z (n_158));
  AOI21D1 g8243__2883(.A1 (rxcounters1_n_757), .A2 (rxcounters1_n_756),
       .B (rxcounters1_ResetByteCounter), .ZN (n_157));
  AN3XD1 g8244__2346(.A1 (LatchedByte[4]), .A2 (LatchedByte[2]), .A3
       (LatchedByte[5]), .Z (n_156));
  NR3D1 g8245__1666(.A1 (rxcounters1_n_747), .A2 (n_106), .A3
       (rxcounters1_n_894), .ZN (n_188));
  OR3XD1 g8246__7410(.A1 (rxcounters1_n_757), .A2 (n_106), .A3
       (rxcounters1_n_747), .Z (n_187));
  IND2D1 g8247__6417(.A1 (n_96), .B1 (n_86), .ZN (n_155));
  ND2D1 g8249__5477(.A1 (n_108), .A2 (MRxDV), .ZN (n_186));
  ND2D1 g8250__2398(.A1 (rxcounters1_n_213), .A2 (n_87), .ZN (n_154));
  ND2D1 g8251__5107(.A1 (n_109), .A2 (CrcHash[4]), .ZN (n_185));
  ND2D1 g8252__6260(.A1 (n_94), .A2 (CrcHash[4]), .ZN (n_184));
  NR2D2 g8253__4319(.A1 (n_95), .A2 (CrcHash[4]), .ZN (n_183));
  NR2XD1 g8255__8428(.A1 (rxcounters1_n_746), .A2 (n_106), .ZN (n_182));
  ND2D1 g8256__5526(.A1 (n_109), .A2 (n_67), .ZN (n_181));
  NR2D2 g8257__6783(.A1 (n_113), .A2 (CrcHash[4]), .ZN (n_180));
  ND2D1 g8258__3680(.A1 (n_97), .A2 (n_67), .ZN (n_179));
  ND2D1 g8259__1617(.A1 (n_97), .A2 (CrcHash[4]), .ZN (n_178));
  IND2D1 g8260__2802(.A1 (n_113), .B1 (CrcHash[4]), .ZN (n_177));
  NR2D3 g8262__1705(.A1 (n_110), .A2 (CrcHash[5]), .ZN (n_176));
  AN2D2 g8263__5122(.A1 (n_93), .A2 (CrcHash[5]), .Z (n_175));
  AN2D2 g8264__8246(.A1 (n_112), .A2 (CrcHash[5]), .Z (n_174));
  AN2D2 g8265__7098(.A1 (n_112), .A2 (n_57), .Z (n_173));
  AN2D2 g8266__6131(.A1 (n_111), .A2 (CrcHash[5]), .Z (n_172));
  AN2D2 g8267__1881(.A1 (n_93), .A2 (n_57), .Z (n_171));
  AN2D2 g8268__5115(.A1 (n_114), .A2 (CrcHash[5]), .Z (n_170));
  AN2D2 g8269__7482(.A1 (n_114), .A2 (n_57), .Z (n_169));
  MAOI22D1 g8270__4733(.A1 (n_64), .A2 (MAC[42]), .B1 (n_64), .B2
       (MAC[42]), .ZN (n_153));
  MAOI22D1 g8271__6161(.A1 (rxcounters1_n_730), .A2 (ByteCnt[15]), .B1
       (rxcounters1_n_730), .B2 (ByteCnt[15]), .ZN (n_152));
  MOAI22D1 g8272__9315(.A1 (rxcounters1_n_898), .A2 (DlyCrcCnt[0]), .B1
       (rxcounters1_n_898), .B2 (DlyCrcCnt[0]), .ZN (n_151));
  MAOI22D1 g8273__9945(.A1 (rxcounters1_n_718), .A2 (ByteCnt[6]), .B1
       (rxcounters1_n_718), .B2 (ByteCnt[6]), .ZN (n_150));
  MAOI22D1 g8274__2883(.A1 (rxcounters1_n_725), .A2 (ByteCnt[10]), .B1
       (rxcounters1_n_725), .B2 (ByteCnt[10]), .ZN (n_149));
  AN4XD1 g8275__2346(.A1 (LatchedByte[7]), .A2 (LatchedByte[6]), .A3
       (LatchedByte[1]), .A4 (LatchedByte[3]), .Z (n_148));
  MAOI22D1 g8276__1666(.A1 (n_49), .A2 (MAC[37]), .B1 (n_49), .B2
       (MAC[37]), .ZN (n_147));
  MUX2ND0 g8277__7410(.I0 (n_63), .I1 (n_54), .S (MAC[33]), .ZN
       (n_146));
  MUX2ND0 g8278__6417(.I0 (n_52), .I1 (n_51), .S (MAC[36]), .ZN
       (n_145));
  MAOI22D1 g8279__5477(.A1 (n_74), .A2 (MAC[38]), .B1 (n_74), .B2
       (MAC[38]), .ZN (n_144));
  MAOI22D1 g8280__2398(.A1 (n_74), .A2 (MAC[22]), .B1 (n_74), .B2
       (MAC[22]), .ZN (n_143));
  MUX2ND0 g8281__5107(.I0 (n_63), .I1 (n_54), .S (MAC[17]), .ZN
       (n_142));
  MUX2ND0 g8282__6260(.I0 (n_52), .I1 (n_51), .S (MAC[20]), .ZN
       (n_141));
  MAOI22D1 g8283__4319(.A1 (n_49), .A2 (MAC[21]), .B1 (n_49), .B2
       (MAC[21]), .ZN (n_140));
  MAOI22D1 g8284__8428(.A1 (n_65), .A2 (MAC[19]), .B1 (n_65), .B2
       (MAC[19]), .ZN (n_139));
  MOAI22D1 g8285__5526(.A1 (n_49), .A2 (MAC[5]), .B1 (n_49), .B2
       (MAC[5]), .ZN (n_138));
  MAOI22D1 g8286__6783(.A1 (n_62), .A2 (MAC[23]), .B1 (n_62), .B2
       (MAC[23]), .ZN (n_137));
  MUX2ND0 g8287__3680(.I0 (n_51), .I1 (n_52), .S (MAC[44]), .ZN
       (n_136));
  MAOI22D1 g8288__1617(.A1 (n_49), .A2 (MAC[45]), .B1 (n_49), .B2
       (MAC[45]), .ZN (n_135));
  MUX2ND0 g8289__2802(.I0 (n_54), .I1 (n_63), .S (MAC[41]), .ZN
       (n_134));
  MAOI22D1 g8290__1705(.A1 (rxcounters1_n_723), .A2 (ByteCnt[9]), .B1
       (rxcounters1_n_723), .B2 (ByteCnt[9]), .ZN (n_133));
  MOAI22D1 g8291__5122(.A1 (n_65), .A2 (MAC[43]), .B1 (n_65), .B2
       (MAC[43]), .ZN (n_132));
  MOAI22D1 g8292__8246(.A1 (n_66), .A2 (MAC[40]), .B1 (n_66), .B2
       (MAC[40]), .ZN (n_131));
  MOAI22D1 g8293__7098(.A1 (n_65), .A2 (MAC[3]), .B1 (n_65), .B2
       (MAC[3]), .ZN (n_130));
  MUX2ND1 g8294__6131(.I0 (n_54), .I1 (n_63), .S (MAC[25]), .ZN
       (n_129));
  MAOI22D1 g8295__1881(.A1 (n_64), .A2 (MAC[26]), .B1 (n_64), .B2
       (MAC[26]), .ZN (n_128));
  MAOI22D1 g8296__5115(.A1 (n_66), .A2 (MAC[24]), .B1 (n_66), .B2
       (MAC[24]), .ZN (n_127));
  MUX2ND0 g8297__7482(.I0 (n_51), .I1 (n_52), .S (MAC[28]), .ZN
       (n_126));
  MUX2ND0 g8298__4733(.I0 (n_54), .I1 (n_63), .S (MAC[9]), .ZN (n_125));
  MAOI22D1 g8299__6161(.A1 (n_66), .A2 (MAC[8]), .B1 (n_66), .B2
       (MAC[8]), .ZN (n_124));
  MUX2ND0 g8300__9315(.I0 (n_52), .I1 (n_51), .S (MAC[12]), .ZN
       (n_123));
  MAOI22D1 g8301__9945(.A1 (n_74), .A2 (MAC[14]), .B1 (n_74), .B2
       (MAC[14]), .ZN (n_122));
  MAOI22D1 g8302__2883(.A1 (n_65), .A2 (MAC[11]), .B1 (n_65), .B2
       (MAC[11]), .ZN (n_121));
  MAOI22D1 g8303__2346(.A1 (n_64), .A2 (MAC[10]), .B1 (n_64), .B2
       (MAC[10]), .ZN (n_120));
  MOAI22D1 g8304__1666(.A1 (n_64), .A2 (MAC[2]), .B1 (n_64), .B2
       (MAC[2]), .ZN (n_119));
  MAOI22D1 g8305__7410(.A1 (n_66), .A2 (MAC[0]), .B1 (n_66), .B2
       (MAC[0]), .ZN (n_118));
  MUX2ND0 g8306__6417(.I0 (n_52), .I1 (n_51), .S (MAC[4]), .ZN (n_117));
  MAOI22D1 g8307__5477(.A1 (n_62), .A2 (MAC[39]), .B1 (n_62), .B2
       (MAC[39]), .ZN (n_116));
  MAOI22D1 g8308__2398(.A1 (n_66), .A2 (MAC[32]), .B1 (n_66), .B2
       (MAC[32]), .ZN (n_115));
  CKND1 g8310(.I (n_110), .ZN (n_111));
  CKND2D1 g8312__5107(.A1 (n_62), .A2 (MAC[15]), .ZN (n_105));
  NR2D1 g8313__6260(.A1 (n_65), .A2 (MAC[35]), .ZN (n_104));
  NR2XD0 g8314__4319(.A1 (n_489), .A2 (\crcrx_Crc[24]_360 ), .ZN
       (n_103));
  NR2XD0 g8315__8428(.A1 (n_491), .A2 (\crcrx_Crc[25]_361 ), .ZN
       (n_102));
  NR2D1 g8316__5526(.A1 (n_64), .A2 (MAC[18]), .ZN (n_101));
  OR2XD1 g8317__6783(.A1 (Initialize_Crc), .A2 (Crc[27]), .Z (n_100));
  ND2D1 g8319__3680(.A1 (n_74), .A2 (MAC[30]), .ZN (n_99));
  NR2D1 g8321__1617(.A1 (CrcHash[0]), .A2 (CrcHash[3]), .ZN (n_114));
  ND2D1 g8322__2802(.A1 (CrcHash[1]), .A2 (CrcHash[2]), .ZN (n_113));
  INR2D1 g8323__1705(.A1 (CrcHash[0]), .B1 (CrcHash[3]), .ZN (n_112));
  ND2D1 g8324__5122(.A1 (CrcHash[0]), .A2 (CrcHash[3]), .ZN (n_110));
  ND2D1 g8325__8246(.A1 (Multicast), .A2 (CrcHashGood), .ZN (n_98));
  INR2D1 g8326__7098(.A1 (CrcHash[2]), .B1 (CrcHash[1]), .ZN (n_109));
  NR2XD0 g8327__6131(.A1 (n_378), .A2 (MRxD[3]), .ZN (n_108));
  CKND2D1 g8328__1881(.A1 (rxcounters1_IFGCounter[1]), .A2
       (rxcounters1_IFGCounter[0]), .ZN (n_107));
  NR2XD1 g8329__5115(.A1 (StateData[1]), .A2 (StateData[0]), .ZN
       (n_106));
  CKND1 g8330(.I (n_94), .ZN (n_95));
  CKND1 g8331(.I (n_91), .ZN (n_90));
  NR2D1 g8332__7482(.A1 (n_343), .A2 (n_376), .ZN (n_85));
  NR2D1 g8333__4733(.A1 (n_49), .A2 (MAC[29]), .ZN (n_84));
  NR2XD0 g8334__6161(.A1 (StatePreamble), .A2 (StateDrop), .ZN (n_83));
  NR2D1 g8335__9315(.A1 (n_62), .A2 (MAC[47]), .ZN (n_82));
  ND2D1 g8336__9945(.A1 (ByteCntMaxFrame), .A2 (StateData[0]), .ZN
       (n_81));
  NR2XD0 g8337__2883(.A1 (rxcounters1_ResetIFGCounter), .A2
       (rxcounters1_IFGCounter[0]), .ZN (n_80));
  NR2XD0 g8338__2346(.A1 (ByteCnt[0]), .A2 (ByteCnt[1]), .ZN (n_79));
  NR2XD0 g8339__1666(.A1 (rxcounters1_ResetByteCounter), .A2
       (ByteCnt[0]), .ZN (n_78));
  NR2D1 g8340__7410(.A1 (CrcHash[1]), .A2 (CrcHash[2]), .ZN (n_97));
  INR2XD0 g8341__6417(.A1 (LatchedByte[0]), .B1 (n_487), .ZN (n_96));
  INR2D1 g8342__5477(.A1 (CrcHash[1]), .B1 (CrcHash[2]), .ZN (n_94));
  INR2D1 g8343__2398(.A1 (CrcHash[3]), .B1 (CrcHash[0]), .ZN (n_93));
  CKND2D1 g8344__5107(.A1 (n_77), .A2 (ByteCnt[11]), .ZN (n_92));
  ND2D1 g8345__6260(.A1 (MRxDV), .A2 (StateIdle), .ZN (n_91));
  CKND2D1 g8346__4319(.A1 (n_71), .A2 (ByteCnt[13]), .ZN (n_89));
  CKND2D1 g8347__8428(.A1 (DlyCrcCnt[1]), .A2 (DlyCrcCnt[0]), .ZN
       (n_88));
  ND2D2 g8348__5526(.A1 (StateSFD), .A2 (DlyCrcEn), .ZN (n_87));
  NR2XD1 g8349__6783(.A1 (RxAbort), .A2 (RxEndFrm), .ZN (n_86));
  CKND1 g8350(.I (rxcounters1_n_726), .ZN (n_77));
  CKND1 g8352(.I (rxcounters1_ResetIFGCounter), .ZN (n_76));
  INVD3 g8360(.I (RxData[6]), .ZN (n_74));
  CKND1 g8361(.I (rxcounters1_ResetByteCounter), .ZN (n_73));
  CKND1 g8362(.I (rxcounters1_n_756), .ZN (n_72));
  CKND1 g8363(.I (rxcounters1_n_728), .ZN (n_71));
  CKND1 g8366(.I (StateData[1]), .ZN (n_70));
  CKND1 g8368(.I (StateSFD), .ZN (n_69));
  CKND1 g8369(.I (rxcounters1_n_898), .ZN (n_68));
  CKND1 g8370(.I (CrcHash[4]), .ZN (n_67));
  INVD2 g8371(.I (RxData[0]), .ZN (n_66));
  INVD3 g8372(.I (RxData[3]), .ZN (n_65));
  INVD2 g8373(.I (RxData[2]), .ZN (n_64));
  CKND1 g8374(.I (n_54), .ZN (n_63));
  INVD2 g8375(.I (RxData[7]), .ZN (n_62));
  DFCND1 rxstatem1_StatePreamble_reg(.CDN (n_0), .CP (MRxClk), .D
       (n_37), .Q (StatePreamble), .QN (n_55));
  INVD2 drc_bufs(.I (n_53), .ZN (n_54));
  INVD1 drc_bufs8379(.I (RxData[1]), .ZN (n_53));
  INVD2 drc_bufs8383(.I (n_51), .ZN (n_52));
  INVD2 drc_bufs8384(.I (RxData[4]), .ZN (n_51));
  INVD2 drc_bufs8388(.I (RxData[5]), .ZN (n_49));
  INVD1 drc_bufs8397(.I (CrcHash[5]), .ZN (n_57));
  CKND1 drc_bufs8400(.I (n_59), .ZN (n_42));
  INVD1 drc_bufs8401(.I (n_292), .ZN (n_59));
  CKND1 drc_bufs8404(.I (n_40), .ZN (n_41));
  INVD1 drc_bufs8405(.I (n_178), .ZN (n_40));
  CKND1 drc_bufs8408(.I (n_38), .ZN (n_39));
  INVD1 drc_bufs8409(.I (n_179), .ZN (n_38));
  BUFFD0 drc7228(.I (n_322), .Z (n_37));
  BUFFD0 drc8417(.I (n_297), .Z (n_34));
  BUFFD0 drc8419(.I (n_323), .Z (n_33));
  BUFFD0 drc8421(.I (n_198), .Z (n_32));
  BUFFD0 drc8423(.I (n_290), .Z (n_31));
  BUFFD0 drc8425(.I (n_194), .Z (n_30));
  INVD1 drc_bufs8432(.I (n_212), .ZN (n_58));
  BUFFD0 drc8435(.I (n_295), .Z (n_29));
  BUFFD0 drc8437(.I (n_296), .Z (n_28));
  CKND1 drc_bufs8439(.I (n_26), .ZN (n_27));
  INVD1 drc_bufs8440(.I (n_177), .ZN (n_26));
  BUFFD0 drc8443(.I (n_313), .Z (n_25));
  BUFFD0 drc8457(.I (n_193), .Z (n_36));
  BUFFD0 drc8459(.I (n_266), .Z (n_35));
  XOR2D1 g7229__3680(.A1 (DlyCrcCnt[0]), .A2 (DlyCrcCnt[1]), .Z (n_24));
  IND2D1 g8474__1617(.A1 (n_106), .B1 (ByteCntEq6), .ZN (n_23));
  DFCNQD1 RxStartFrm_d_reg(.CDN (n_0), .CP (MRxClk), .D (n_14), .Q
       (RxStartFrm_d));
  DFCNQD2 RxEndFrm_reg(.CDN (n_0), .CP (MRxClk), .D (n_9), .Q
       (RxEndFrm));
  MOAI22D1 g3901__2802(.A1 (n_487), .A2 (DlyCrcEn), .B1 (n_8), .B2
       (DlyCrcEn), .ZN (n_14));
  AO221D0 g3902__1705(.A1 (n_4), .A2 (\crcrx_Crc[20]_356 ), .B1
       (n_416), .B2 (n_3), .C (Initialize_Crc), .Z (n_13));
  AO211D1 g3903__5122(.A1 (n_490), .A2 (\crcrx_Crc[23]_359 ), .B (n_7),
       .C (Initialize_Crc), .Z (n_12));
  AO211D1 g3904__8246(.A1 (n_493), .A2 (\crcrx_Crc[18]_354 ), .B (n_6),
       .C (Initialize_Crc), .Z (n_11));
  AO211D1 g3905__7098(.A1 (n_492), .A2 (\crcrx_Crc[21]_357 ), .B (n_5),
       .C (Initialize_Crc), .Z (n_10));
  AO31D1 g3906__6131(.A1 (n_484), .A2 (n_2), .A3 (StateData[1]), .B
       (RxEndFrm_d), .Z (n_9));
  NR3D1 g3913__1881(.A1 (n_486), .A2 (DlyCrcCnt[3]), .A3
       (DlyCrcCnt[2]), .ZN (n_8));
  DFCNQD1 RxValid_d_reg(.CDN (n_0), .CP (MRxClk), .D (GenerateRxValid),
       .Q (RxValid_d));
  DFQD1 CrcHashGood_reg(.CP (MRxClk), .D (n_482), .Q (CrcHashGood));
  NR2XD0 g3932__5115(.A1 (n_490), .A2 (\crcrx_Crc[23]_359 ), .ZN (n_7));
  NR2XD0 g3933__7482(.A1 (n_493), .A2 (\crcrx_Crc[18]_354 ), .ZN (n_6));
  NR2XD0 g3934__4733(.A1 (n_492), .A2 (\crcrx_Crc[21]_357 ), .ZN (n_5));
  CKND1 g3935(.I (n_416), .ZN (n_4));
  CKND1 g3936(.I (\crcrx_Crc[20]_356 ), .ZN (n_3));
  BUFFD2 drc_bufs3944(.I (n_20), .Z (RxData[5]));
  BUFFD2 drc_bufs3945(.I (n_18), .Z (RxData[3]));
  AOI32D1 g8509__6161(.A1 (n_267), .A2 (rxcounters1_n_895), .A3
       (StateData[0]), .B1 (n_487), .B2 (n_161), .ZN (n_648));
  BUFFD0 drc8549(.I (n_126), .Z (n_660));
  XOR2D1 g8553__9315(.A1 (n_49), .A2 (MAC[13]), .Z (n_664));
  CKND0 g2923(.I (Reset), .ZN (n_216));
  INVD1 g2924(.I (n_234), .ZN (NibCntEq15));
  INVD1 g2925(.I (n_235), .ZN (NibCntEq7));
  OA21D1 g4639__9945(.A1 (n_213), .A2 (n_212), .B (n_201), .Z
       (NibbleMinFl));
  OAI222D1 g4640__2883(.A1 (n_210), .A2 (n_211), .B1 (n_202), .B2
       (n_208), .C1 (n_200), .C2 (n_204), .ZN (n_213));
  AOI21D1 g4641__2346(.A1 (n_207), .A2 (n_198), .B (n_211), .ZN
       (n_212));
  OAI21D1 g4642(.A1 (n_195), .A2 (\NibCnt[12]_455 ), .B (n_209), .ZN
       (n_211));
  OAI211D1 g4643(.A1 (\NibCnt[8]_451 ), .A2 (n_186), .B (n_206), .C
       (n_203), .ZN (n_210));
  CKND1 g4644(.I (n_208), .ZN (n_209));
  OR2XD1 g4645(.A1 (n_205), .A2 (n_200), .Z (n_208));
  AOI22D1 g4646(.A1 (n_203), .A2 (n_193), .B1 (n_179), .B2
       (\NibCnt[11]_454 ), .ZN (n_207));
  OAI221D1 g4647(.A1 (n_196), .A2 (n_178), .B1 (n_196), .B2 (n_170), .C
       (n_194), .ZN (n_206));
  OAI22D1 g4648(.A1 (n_199), .A2 (\NibCnt[14]_457 ), .B1 (n_187), .B2
       (\NibCnt[13]_456 ), .ZN (n_205));
  AOI22D1 g4649(.A1 (n_191), .A2 (\NibCnt[15]_458 ), .B1 (n_199), .B2
       (\NibCnt[14]_457 ), .ZN (n_204));
  NR2D1 g4650(.A1 (n_197), .A2 (n_192), .ZN (n_203));
  AOI22D1 g4651(.A1 (n_187), .A2 (\NibCnt[13]_456 ), .B1 (n_195), .B2
       (\NibCnt[12]_455 ), .ZN (n_202));
  MOAI22D1 g4652(.A1 (n_188), .A2 (MinFL[15]), .B1 (n_188), .B2
       (MinFL[15]), .ZN (n_201));
  NR2XD0 g4653(.A1 (n_191), .A2 (\NibCnt[15]_458 ), .ZN (n_200));
  AOI21D1 g4654(.A1 (n_185), .A2 (MinFL[13]), .B (n_181), .ZN (n_199));
  IND3D1 g4655(.A1 (n_192), .B1 (\NibCnt[10]_453 ), .B2 (n_190), .ZN
       (n_198));
  OAI22D1 g4656(.A1 (n_190), .A2 (\NibCnt[10]_453 ), .B1 (n_176), .B2
       (\NibCnt[9]_452 ), .ZN (n_197));
  OR2XD1 g4657(.A1 (n_189), .A2 (n_183), .Z (n_196));
  AOI21D1 g4658(.A1 (n_177), .A2 (MinFL[11]), .B (n_175), .ZN (n_195));
  AOI32D1 g4659(.A1 (n_180), .A2 (n_184), .A3 (NibCnt[6]), .B1 (n_173),
       .B2 (\NibCnt[7]_450 ), .ZN (n_194));
  AO22D0 g4660(.A1 (n_176), .A2 (\NibCnt[9]_452 ), .B1 (\NibCnt[8]_451
       ), .B2 (n_186), .Z (n_193));
  NR2XD0 g4661(.A1 (n_179), .A2 (\NibCnt[11]_454 ), .ZN (n_192));
  AOI21D1 g4662(.A1 (n_182), .A2 (MinFL[14]), .B (n_188), .ZN (n_191));
  OAI22D1 g4663(.A1 (n_180), .A2 (NibCnt[6]), .B1 (n_169), .B2
       (NibCnt[5]), .ZN (n_189));
  AOI21D1 g4664(.A1 (n_174), .A2 (MinFL[9]), .B (n_172), .ZN (n_190));
  NR2XD1 g4665(.A1 (n_182), .A2 (MinFL[14]), .ZN (n_188));
  OA21D0 g4666(.A1 (n_175), .A2 (n_117), .B (n_185), .Z (n_187));
  AOI21D1 g4667(.A1 (n_171), .A2 (MinFL[7]), .B (n_168), .ZN (n_186));
  CKND1 g4668(.I (n_183), .ZN (n_184));
  CKND1 g4669(.I (n_182), .ZN (n_181));
  CKND2D1 g4670(.A1 (n_175), .A2 (n_117), .ZN (n_185));
  NR2D1 g4671(.A1 (n_173), .A2 (\NibCnt[7]_450 ), .ZN (n_183));
  CKND2D1 g4672(.A1 (n_175), .A2 (n_134), .ZN (n_182));
  AOI22D1 g4673(.A1 (n_169), .A2 (NibCnt[5]), .B1 (n_162), .B2
       (NibCnt[4]), .ZN (n_178));
  AOI21D1 g4674(.A1 (n_167), .A2 (MinFL[5]), .B (n_165), .ZN (n_180));
  OA21D0 g4675(.A1 (n_172), .A2 (n_116), .B (n_177), .Z (n_179));
  CKND2D1 g4676(.A1 (n_172), .A2 (n_116), .ZN (n_177));
  OA21D0 g4677(.A1 (n_168), .A2 (n_114), .B (n_174), .Z (n_176));
  AN3D1 g4678(.A1 (n_172), .A2 (n_116), .A3 (n_120), .Z (n_175));
  CKND2D1 g4679(.A1 (n_168), .A2 (n_114), .ZN (n_174));
  OA21D0 g4680(.A1 (n_165), .A2 (n_115), .B (n_171), .Z (n_173));
  AN3D1 g4681(.A1 (n_168), .A2 (n_114), .A3 (n_125), .Z (n_172));
  OAI21D1 g4682(.A1 (n_162), .A2 (NibCnt[4]), .B (n_163), .ZN (n_170));
  CKND2D1 g4683(.A1 (n_165), .A2 (n_115), .ZN (n_171));
  AOI21D1 g4684(.A1 (n_164), .A2 (MinFL[4]), .B (n_166), .ZN (n_169));
  AN3D1 g4685(.A1 (n_165), .A2 (n_115), .A3 (n_127), .Z (n_168));
  CKND1 g4686(.I (n_166), .ZN (n_167));
  NR2XD0 g4687(.A1 (n_164), .A2 (MinFL[4]), .ZN (n_166));
  CKAN2D1 g4688(.A1 (n_160), .A2 (n_133), .Z (n_165));
  CKND1 g4689(.I (n_160), .ZN (n_164));
  AN4XD1 g4690(.A1 (n_161), .A2 (n_112), .A3 (n_158), .A4 (n_135), .Z
       (MaxFrame));
  MAOI222D1 g4691(.A (n_113), .B (n_153), .C (n_121), .ZN (n_163));
  AOI21D1 g4692(.A1 (n_152), .A2 (MinFL[3]), .B (n_160), .ZN (n_162));
  OA221D0 g4693(.A1 (n_131), .A2 (ByteCnt[6]), .B1 (MaxFL[5]), .B2
       (n_129), .C (n_159), .Z (n_161));
  NR2XD1 g4694(.A1 (n_152), .A2 (MinFL[3]), .ZN (n_160));
  NR3D0 g4695(.A1 (n_157), .A2 (n_143), .A3 (n_138), .ZN (n_159));
  NR3D0 g4696(.A1 (n_151), .A2 (n_147), .A3 (HugEn), .ZN (n_158));
  AO221D0 g4697(.A1 (n_129), .A2 (MaxFL[5]), .B1 (n_131), .B2
       (ByteCnt[6]), .C (n_154), .Z (n_157));
endmodule
