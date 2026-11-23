-- =====================================================================
--  DrogueriaGestión
--  Script 03: Datos de prueba (ficticios)
--  Las fechas se calculan respecto al día de instalación (CURDATE/NOW)
--  para que siempre existan lotes vigentes, próximos a vencer y vencidos.
-- =====================================================================

USE drogueria_gestion;

-- ---------------------------------------------------------------------
--  Roles, usuarios y configuración
-- ---------------------------------------------------------------------
INSERT INTO roles (id_rol, nombre, descripcion) VALUES
(1, 'ADMINISTRADOR', 'Acceso total: usuarios, configuración, auditoría y todos los módulos'),
(2, 'REGENTE',       'Regente de farmacia: medicamentos, inventario, ventas, anulaciones, proveedores y reportes'),
(3, 'VENDEDOR',      'Auxiliar de dispensación: ventas, clientes y consulta de medicamentos'),
(4, 'BODEGA',        'Encargado de inventario: entradas, ajustes, lotes, vencimientos y proveedores');

-- Contraseñas de prueba (ver README): se almacenan con hash scrypt, nunca en texto plano.
INSERT INTO usuarios (id_usuario, id_rol, documento, nombres, apellidos, email, usuario, password_hash) VALUES
(1, 1, '1121000001', 'Andrea Camila', 'Rojas Pinzón', 'admin@drogueriagestion.com.co', 'admin', 'scrypt:32768:8:1$H8OaKCIVoxWwlzCZ$cf06a121fe60ccd9e9c47bf4d977106e16e322019db0c632003088bbccd51ba517bf44afb1bda7df43fdbdb084ca5369a8259321f0766698f4ae09d88a1783da'),
(2, 2, '1121000002', 'Jorge Iván', 'Pardo Gómez', 'regente@drogueriagestion.com.co', 'regente', 'scrypt:32768:8:1$XBrKt1BNBjpyjwEp$877f81722f30cc022aefe1767c312b0aab902f1e47bf3b4c8f55077d4c26c9b9fd6c704b09ab46d9f9983e19312a734bd5773342c03bcf0feb35611a05e0e9b2'),
(3, 3, '1121000003', 'Laura Sofía', 'Méndez Ruiz', 'ventas@drogueriagestion.com.co', 'vendedor', 'scrypt:32768:8:1$HHLwKqLln9Feb1TL$8ba3af458973c36c23dc897ebea755759e2fbf1b1707cfa850b729c15179f361433868b78c1fc2b338191700d48b06462c12b02dd062f04cde2ab7bec9c6edd0'),
(4, 4, '1121000004', 'Miguel Ángel', 'Suárez León', 'bodega@drogueriagestion.com.co', 'bodega', 'scrypt:32768:8:1$VdOmRbXgTUdkCbz4$6dd8715578bc22cb347b8e2e67dc1d367929fe473498a780caa0f8a2676495139f896629572c86b669db9d8727bbab89a200a46331bf221cc32f84ffbbedcb59');

INSERT INTO configuracion (clave, valor, descripcion) VALUES
('nombre_drogueria', 'Droguería Salud Llanera', 'Nombre comercial del establecimiento'),
('nit', '901.234.567-8', 'NIT del establecimiento'),
('direccion', 'Calle 38 # 30A-15, Centro, Villavicencio, Meta', 'Dirección del establecimiento'),
('telefono', '(608) 662 0000', 'Teléfono de contacto'),
('email', 'contacto@saludllanera.com.co', 'Correo electrónico de contacto'),
('mensaje_factura', 'Gracias por su compra. Conserve este comprobante.', 'Mensaje al pie del comprobante de venta'),
('descuento_maximo_vendedor', '10', 'Descuento máximo (%) que puede aplicar un vendedor; regente y administrador no tienen tope');

INSERT INTO consecutivos (tipo, prefijo, ultimo_numero) VALUES ('VENTA', 'FV', 0);

-- ---------------------------------------------------------------------
--  Categorías terapéuticas
-- ---------------------------------------------------------------------
INSERT INTO categorias (id_categoria, nombre, descripcion) VALUES
(1,  'Analgésicos y antipiréticos', 'Alivio del dolor y control de la fiebre'),
(2,  'Antiinflamatorios (AINE)', 'Antiinflamatorios no esteroideos de uso oral y tópico'),
(3,  'Antibióticos', 'Antiinfecciosos de venta bajo fórmula médica'),
(4,  'Cardiovasculares', 'Antihipertensivos, hipolipemiantes y antiagregantes'),
(5,  'Antidiabéticos', 'Control de la glucemia'),
(6,  'Antihistamínicos', 'Tratamiento de alergias'),
(7,  'Gastrointestinales', 'Antiácidos, protectores gástricos y antidiarreicos'),
(8,  'Respiratorios', 'Broncodilatadores, mucolíticos y antitusivos'),
(9,  'Vitaminas y suplementos', 'Vitaminas, minerales y suplementos nutricionales'),
(10, 'Dermatológicos', 'Cremas y ungüentos de uso tópico'),
(11, 'Antiparasitarios y antimicóticos', 'Tratamiento de parásitos y hongos'),
(12, 'Control especial', 'Medicamentos de control especial (psicotrópicos)'),
(13, 'Primeros auxilios y cuidado', 'Material de curación y productos de cuidado');

-- ---------------------------------------------------------------------
--  Proveedores
-- ---------------------------------------------------------------------
INSERT INTO proveedores (id_proveedor, nit, razon_social, nombre_contacto, telefono, email, direccion, ciudad) VALUES
(1, '900123456-1', 'Distribuidora Farmacéutica del Llano S.A.S.', 'Carlos Andrés Rey', '3104567001', 'pedidos@farmallano.com.co', 'Av. 40 # 26C-10', 'Villavicencio'),
(2, '830045678-2', 'Mayoristas Andinos de Medicamentos Ltda.', 'Paola Andrea Vargas', '3157894002', 'ventas@mayoristasandinos.com.co', 'Calle 13 # 65-21', 'Bogotá D.C.'),
(3, '901234567-3', 'Medisalud Distribuciones S.A.S.', 'Hernán Darío Quintero', '3209871003', 'comercial@medisalud.com.co', 'Carrera 22 # 7-45', 'Villavicencio'),
(4, '860512345-4', 'Farmacéuticos Unidos de Colombia S.A.', 'Natalia Pérez Ortiz', '3012347004', 'servicio@farmaunidos.com.co', 'Autopista Sur # 71-75', 'Bogotá D.C.'),
(5, '900765432-5', 'Insumos Médicos Orinoquía S.A.S.', 'Ricardo Salazar Mora', '3184561005', 'insumos@orinoquia.com.co', 'Km 2 Vía Puerto López', 'Villavicencio');

-- ---------------------------------------------------------------------
--  Medicamentos
-- ---------------------------------------------------------------------
INSERT INTO medicamentos (id_medicamento, codigo, nombre, principio_activo, concentracion, forma_farmaceutica, presentacion,
    laboratorio, registro_invima, id_categoria, requiere_formula, es_controlado, precio_compra, precio_venta,
    iva_porcentaje, stock_minimo, ubicacion) VALUES
(1, '7702030509027', 'Acetaminofén 500 mg', 'Acetaminofén', '500 mg', 'Tableta', 'Caja x 20 tabletas', 'Genfar', 'INVIMA 2017M-2857850', 1, 0, 0, 2800, 4500, 0, 30, 'A1'),
(2, '7705716095802', 'Acetaminofén jarabe', 'Acetaminofén', '150 mg/5 mL', 'Jarabe', 'Frasco x 90 mL', 'MK', 'INVIMA 2016M-9225646', 1, 0, 0, 4200, 7500, 0, 15, 'A1'),
(3, '7708212920593', 'Dipirona 500 mg', 'Metamizol sódico', '500 mg', 'Tableta', 'Caja x 10 tabletas', 'La Santé', 'INVIMA 2019M-7664202', 1, 0, 0, 3000, 5200, 0, 15, 'A1'),
(4, '7706375207868', 'Ibuprofeno 400 mg', 'Ibuprofeno', '400 mg', 'Tableta', 'Caja x 10 tabletas', 'Genfar', 'INVIMA 2021M-7314012', 2, 0, 0, 2500, 4800, 0, 30, 'A2'),
(5, '7709917726066', 'Ibuprofeno suspensión', 'Ibuprofeno', '100 mg/5 mL', 'Suspensión', 'Frasco x 120 mL', 'MK', 'INVIMA 2021M-2504328', 2, 0, 0, 5500, 9800, 0, 10, 'A2'),
(6, '7706549621184', 'Naproxeno 250 mg', 'Naproxeno sódico', '250 mg', 'Tableta', 'Caja x 10 tabletas', 'La Santé', 'INVIMA 2023M-3363714', 2, 0, 0, 3200, 6000, 0, 15, 'A2'),
(7, '7707774981744', 'Diclofenaco 50 mg', 'Diclofenaco sódico', '50 mg', 'Tableta', 'Caja x 30 tabletas', 'Genfar', 'INVIMA 2016M-7188185', 2, 0, 0, 3500, 6500, 0, 15, 'A2'),
(8, '7706856369309', 'Diclofenaco gel', 'Diclofenaco dietilamonio', '1 %', 'Gel', 'Tubo x 50 g', 'Procaps', 'INVIMA 2022M-2521428', 2, 0, 0, 7800, 13500, 0, 8, 'A2'),
(9, '7705795107404', 'Amoxicilina 500 mg', 'Amoxicilina', '500 mg', 'Cápsula', 'Caja x 50 cápsulas', 'Genfar', 'INVIMA 2024M-9238128', 3, 1, 0, 9500, 16500, 0, 10, 'B1'),
(10, '7707548333555', 'Azitromicina 500 mg', 'Azitromicina', '500 mg', 'Tableta', 'Caja x 3 tabletas', 'MK', 'INVIMA 2022M-9039473', 3, 1, 0, 6200, 11900, 0, 10, 'B1'),
(11, '7704458192345', 'Cefalexina 500 mg', 'Cefalexina', '500 mg', 'Cápsula', 'Caja x 10 cápsulas', 'La Santé', 'INVIMA 2019M-3164241', 3, 1, 0, 5800, 10500, 0, 10, 'B1'),
(12, '7704513851069', 'Ciprofloxacino 500 mg', 'Ciprofloxacino', '500 mg', 'Tableta', 'Caja x 10 tabletas', 'Genfar', 'INVIMA 2024M-2720946', 3, 1, 0, 4500, 8900, 0, 10, 'B1'),
(13, '7707139267178', 'Amoxicilina suspensión', 'Amoxicilina', '250 mg/5 mL', 'Polvo para suspensión', 'Frasco x 100 mL', 'MK', 'INVIMA 2018M-9088515', 3, 1, 0, 7000, 12500, 0, 8, 'B1'),
(14, '7704798065994', 'Losartán 50 mg', 'Losartán potásico', '50 mg', 'Tableta', 'Caja x 30 tabletas', 'Genfar', 'INVIMA 2017M-8663770', 4, 1, 0, 4200, 8500, 0, 20, 'B2'),
(15, '7708191077343', 'Enalapril 20 mg', 'Enalapril maleato', '20 mg', 'Tableta', 'Caja x 30 tabletas', 'La Santé', 'INVIMA 2024M-5211189', 4, 1, 0, 3600, 7200, 0, 15, 'B2'),
(16, '7707699273039', 'Amlodipino 5 mg', 'Amlodipino besilato', '5 mg', 'Tableta', 'Caja x 30 tabletas', 'MK', 'INVIMA 2020M-9420478', 4, 1, 0, 3900, 7800, 0, 15, 'B2'),
(17, '7708294244131', 'Atorvastatina 20 mg', 'Atorvastatina cálcica', '20 mg', 'Tableta', 'Caja x 30 tabletas', 'Procaps', 'INVIMA 2022M-8265655', 4, 1, 0, 8500, 15900, 0, 10, 'B2'),
(18, '7706164832776', 'Ácido acetilsalicílico 100 mg', 'Ácido acetilsalicílico', '100 mg', 'Tableta', 'Caja x 30 tabletas', 'Bayer', 'INVIMA 2020M-1155640', 4, 0, 0, 5200, 9500, 0, 15, 'B2'),
(19, '7701142203221', 'Metformina 850 mg', 'Metformina clorhidrato', '850 mg', 'Tableta', 'Caja x 30 tabletas', 'Genfar', 'INVIMA 2023M-9772618', 5, 1, 0, 3800, 7500, 0, 20, 'B3'),
(20, '7709276220344', 'Glibenclamida 5 mg', 'Glibenclamida', '5 mg', 'Tableta', 'Caja x 30 tabletas', 'La Santé', 'INVIMA 2021M-4352718', 5, 1, 0, 3100, 6200, 0, 10, 'B3'),
(21, '7707380470856', 'Loratadina 10 mg', 'Loratadina', '10 mg', 'Tableta', 'Caja x 10 tabletas', 'Genfar', 'INVIMA 2024M-9340912', 6, 0, 0, 1800, 3900, 0, 20, 'A3'),
(22, '7708765125956', 'Cetirizina 10 mg', 'Cetirizina diclorhidrato', '10 mg', 'Tableta', 'Caja x 10 tabletas', 'MK', 'INVIMA 2024M-1564049', 6, 0, 0, 2200, 4500, 0, 15, 'A3'),
(23, '7708865815672', 'Loratadina jarabe', 'Loratadina', '5 mg/5 mL', 'Jarabe', 'Frasco x 60 mL', 'La Santé', 'INVIMA 2021M-8678186', 6, 0, 0, 4500, 8200, 0, 8, 'A3'),
(24, '7705717480361', 'Omeprazol 20 mg', 'Omeprazol', '20 mg', 'Cápsula', 'Caja x 30 cápsulas', 'Genfar', 'INVIMA 2024M-5342466', 7, 0, 0, 3500, 7900, 0, 25, 'A4'),
(25, '7705145795381', 'Esomeprazol 40 mg', 'Esomeprazol magnésico', '40 mg', 'Tableta', 'Caja x 14 tabletas', 'Procaps', 'INVIMA 2022M-9038740', 7, 1, 0, 12500, 22900, 0, 8, 'A4'),
(26, '7705037861054', 'Hidróxido de aluminio y magnesio', 'Hidróxido de aluminio + hidróxido de magnesio', '400/400 mg/5 mL', 'Suspensión', 'Frasco x 360 mL', 'MK', 'INVIMA 2020M-9362112', 7, 0, 0, 6800, 11500, 0, 10, 'A4'),
(27, '7702589690976', 'Loperamida 2 mg', 'Loperamida clorhidrato', '2 mg', 'Tableta', 'Caja x 6 tabletas', 'La Santé', 'INVIMA 2019M-7900650', 7, 0, 0, 2100, 4200, 0, 10, 'A4'),
(28, '7705923573028', 'Sales de rehidratación oral', 'Glucosa + electrolitos', '27,9 g', 'Sobre', 'Sobre x 27,9 g', 'Genfar', 'INVIMA 2016M-2546333', 7, 0, 0, 900, 2000, 0, 30, 'A4'),
(29, '7705295886288', 'Salbutamol inhalador', 'Salbutamol sulfato', '100 mcg/dosis', 'Inhalador', 'Frasco x 200 dosis', 'Genfar', 'INVIMA 2024M-2393608', 8, 1, 0, 11000, 19500, 0, 8, 'C1'),
(30, '7701853803852', 'Ambroxol jarabe', 'Ambroxol clorhidrato', '30 mg/5 mL', 'Jarabe', 'Frasco x 120 mL', 'MK', 'INVIMA 2017M-1749254', 8, 0, 0, 5200, 9500, 0, 10, 'C1'),
(31, '7709402531820', 'Dextrometorfano jarabe', 'Dextrometorfano bromhidrato', '15 mg/5 mL', 'Jarabe', 'Frasco x 120 mL', 'La Santé', 'INVIMA 2021M-3596457', 8, 0, 0, 5800, 10200, 0, 10, 'C1'),
(32, '7705317005189', 'Vitamina C 500 mg', 'Ácido ascórbico', '500 mg', 'Tableta masticable', 'Frasco x 100 tabletas', 'Procaps', 'INVIMA 2023M-3262652', 9, 0, 0, 9500, 16900, 0, 10, 'C2'),
(33, '7703344208658', 'Complejo B', 'Tiamina + piridoxina + cianocobalamina', '100/5/0,05 mg', 'Tableta', 'Caja x 30 tabletas', 'La Santé', 'INVIMA 2023M-3201443', 9, 0, 0, 4800, 8900, 0, 10, 'C2'),
(34, '7707462729157', 'Ácido fólico 1 mg', 'Ácido fólico', '1 mg', 'Tableta', 'Caja x 30 tabletas', 'Genfar', 'INVIMA 2017M-8009167', 9, 0, 0, 2200, 4500, 0, 10, 'C2'),
(35, '7703871421313', 'Clotrimazol crema', 'Clotrimazol', '1 %', 'Crema', 'Tubo x 40 g', 'Genfar', 'INVIMA 2018M-6133900', 11, 0, 0, 3300, 6500, 0, 10, 'C3'),
(36, '7707475530314', 'Betametasona crema', 'Betametasona dipropionato', '0,05 %', 'Crema', 'Tubo x 40 g', 'MK', 'INVIMA 2022M-3492025', 10, 1, 0, 4200, 8200, 0, 8, 'C3'),
(37, '7706139774956', 'Albendazol 400 mg', 'Albendazol', '400 mg', 'Tableta', 'Caja x 1 tableta', 'Genfar', 'INVIMA 2016M-2780632', 11, 0, 0, 1500, 3500, 0, 15, 'C3'),
(38, '7701315393763', 'Metronidazol 500 mg', 'Metronidazol', '500 mg', 'Tableta', 'Caja x 20 tabletas', 'La Santé', 'INVIMA 2021M-6929115', 11, 1, 0, 4000, 7800, 0, 10, 'C3'),
(39, '7705059049801', 'Clonazepam 2 mg', 'Clonazepam', '2 mg', 'Tableta', 'Caja x 30 tabletas', 'Lafrancol', 'INVIMA 2016M-9562887', 12, 1, 1, 6500, 12900, 0, 5, 'D1'),
(40, '7707339476609', 'Alprazolam 0,5 mg', 'Alprazolam', '0,5 mg', 'Tableta', 'Caja x 30 tabletas', 'MK', 'INVIMA 2020M-8552102', 12, 1, 1, 7200, 13800, 0, 5, 'D1'),
(41, '7705816259704', 'Alcohol antiséptico 70 %', 'Alcohol etílico', '70 %', 'Solución', 'Frasco x 350 mL', 'JGB', NULL, 13, 0, 0, 3500, 6200, 19, 15, 'E1'),
(42, '7703231723970', 'Gasa estéril', 'Gasa de algodón', '10 x 10 cm', 'Material de curación', 'Paquete x 10 unidades', 'Insumos Orinoquía', NULL, 13, 0, 0, 1800, 3500, 19, 15, 'E1'),
(43, '7704053217866', 'Apósitos adhesivos', 'Apósito adhesivo', '1,9 x 7,2 cm', 'Material de curación', 'Caja x 30 unidades', 'Insumos Orinoquía', NULL, 13, 0, 0, 2800, 5200, 19, 10, 'E1'),
(44, '7701146684679', 'Suero fisiológico', 'Cloruro de sodio', '0,9 %', 'Solución', 'Frasco x 500 mL', 'Corpaul', 'INVIMA 2018M-1758944', 13, 0, 0, 3200, 5900, 0, 10, 'E1');

-- ---------------------------------------------------------------------
--  Clientes (id 1 = consumidor final)
-- ---------------------------------------------------------------------
INSERT INTO clientes (id_cliente, tipo_documento, numero_documento, nombres, apellidos, telefono, email, direccion, fecha_nacimiento, autoriza_datos) VALUES
(1,  'CC',  '222222222222', 'Consumidor', 'Final', NULL, NULL, NULL, NULL, 0),
(2,  'CC',  '1121845632', 'María Fernanda', 'López Rojas', '3104567890', 'mafe.lopez@ejemplo.com', 'Calle 37 # 29-45, Barzal', '1988-04-12', 1),
(3,  'CC',  '17345678', 'José Antonio', 'Rincón Pardo', '3112345678', NULL, 'Carrera 33 # 15-20, La Esperanza', '1959-09-03', 1),
(4,  'CC',  '40189234', 'Luz Marina', 'Gutiérrez Cruz', '3209876543', 'luzma.gutierrez@ejemplo.com', 'Manzana 4 Casa 12, Ciudadela La Madrid', '1970-02-25', 1),
(5,  'TI',  '1121987654', 'Santiago', 'Herrera Castro', '3001239876', NULL, 'Calle 15 # 40-12, El Buque', '2010-07-19', 1),
(6,  'CC',  '1006789123', 'Valentina', 'Ruiz Ospina', '3014567812', 'vale.ruiz@ejemplo.com', 'Carrera 45 # 23-08, Los Centauros', '1999-11-30', 1),
(7,  'CE',  '987654', 'Carlos Eduardo', 'Pérez Mendoza', '3156782345', NULL, 'Calle 7 Sur # 45-30, Porfía', '1985-05-05', 0),
(8,  'CC',  '86045123', 'Andrés Felipe', 'Moreno Díaz', '3187654321', 'afmoreno@ejemplo.com', 'Transversal 25 # 33-10, San Benito', '1979-01-14', 1),
(9,  'CC',  '1121876543', 'Daniela', 'Castaño Vargas', '3045678901', 'dani.castano@ejemplo.com', 'Carrera 19 # 9-60, Villa Julia', '1995-08-08', 1),
(10, 'NIT', '900456789', 'Fundación Hogar del Adulto Mayor Llano Verde', NULL, '6086612345', 'compras@llanoverde.org', 'Vereda Apiay, Km 5', NULL, 1),
(11, 'CC',  '21234567', 'Gloria Inés', 'Beltrán Silva', '3123456780', NULL, 'Calle 26 # 38-15, Siete de Agosto', '1952-03-17', 1),
(12, 'CC',  '1122334455', 'Julián David', 'Torres Medina', '3176549870', 'jdtorres@ejemplo.com', 'Carrera 30 # 41-22, Caudal', '2001-06-21', 0);

-- ---------------------------------------------------------------------
--  Entradas de mercancía (dos facturas por proveedor)
-- ---------------------------------------------------------------------
INSERT INTO entradas (id_entrada, id_proveedor, numero_factura, fecha_entrada, observaciones, id_usuario) VALUES
(1, 1, 'FP-12951A', NOW() - INTERVAL 121 DAY - INTERVAL 1 HOUR, 'Pedido inicial', 4),
(2, 1, 'FP-16234B', NOW() - INTERVAL 98 DAY - INTERVAL 8 HOUR, 'Pedido de reposición', 4),
(3, 2, 'FP-29233A', NOW() - INTERVAL 124 DAY - INTERVAL 4 HOUR, 'Pedido inicial', 4),
(4, 2, 'FP-29385B', NOW() - INTERVAL 100 DAY - INTERVAL 8 HOUR, 'Pedido de reposición', 4),
(5, 3, 'FP-32681A', NOW() - INTERVAL 127 DAY - INTERVAL 1 HOUR, 'Pedido inicial', 4),
(6, 3, 'FP-34658B', NOW() - INTERVAL 102 DAY - INTERVAL 3 HOUR, 'Pedido de reposición', 4),
(7, 4, 'FP-47891A', NOW() - INTERVAL 130 DAY - INTERVAL 4 HOUR, 'Pedido inicial', 4),
(8, 4, 'FP-49975B', NOW() - INTERVAL 104 DAY - INTERVAL 3 HOUR, 'Pedido de reposición', 4),
(9, 5, 'FP-59042A', NOW() - INTERVAL 133 DAY - INTERVAL 3 HOUR, 'Pedido inicial', 4),
(10, 5, 'FP-58226B', NOW() - INTERVAL 106 DAY - INTERVAL 3 HOUR, 'Pedido de reposición', 4);

-- ---------------------------------------------------------------------
--  Lotes (existencias con fechas de vencimiento relativas a hoy)
-- ---------------------------------------------------------------------
INSERT INTO lotes (id_lote, id_medicamento, id_proveedor, numero_lote, fecha_fabricacion, fecha_vencimiento,
    cantidad_inicial, cantidad_actual, costo_unitario, fecha_ingreso) VALUES
(1, 1, 1, 'GF25E291', CURDATE() + INTERVAL -331 DAY, CURDATE() + INTERVAL 399 DAY, 57, 57, 2750, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(2, 1, 1, 'GF24H609', CURDATE() + INTERVAL -148 DAY, CURDATE() + INTERVAL 646 DAY, 35, 35, 2900, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 2)),
(3, 2, 2, 'MK25E578', CURDATE() + INTERVAL -712 DAY, CURDATE() + INTERVAL 18 DAY, 25, 25, 4100, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(4, 2, 2, 'MK26H555', CURDATE() + INTERVAL -310 DAY, CURDATE() + INTERVAL 420 DAY, 40, 40, 4050, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 4)),
(5, 3, 3, 'LS23A195', CURDATE() + INTERVAL -262 DAY, CURDATE() + INTERVAL 468 DAY, 90, 90, 3050, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(6, 3, 3, 'LS24G658', CURDATE() + INTERVAL -166 DAY, CURDATE() + INTERVAL 564 DAY, 43, 43, 3050, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 6)),
(7, 4, 1, 'GF26K686', CURDATE() + INTERVAL -437 DAY, CURDATE() + INTERVAL 293 DAY, 41, 41, 2550, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(8, 4, 1, 'GF23B735', CURDATE() + INTERVAL -150 DAY, CURDATE() + INTERVAL 580 DAY, 52, 52, 2550, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 2)),
(9, 5, 2, 'MK23J401', CURDATE() + INTERVAL -246 DAY, CURDATE() + INTERVAL 484 DAY, 88, 88, 5500, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(10, 6, 3, 'LS26C203', CURDATE() + INTERVAL -668 DAY, CURDATE() + INTERVAL 62 DAY, 30, 30, 3250, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(11, 6, 3, 'LS22G275', CURDATE() + INTERVAL -220 DAY, CURDATE() + INTERVAL 510 DAY, 40, 40, 3100, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 6)),
(12, 7, 1, 'GF22I421', CURDATE() + INTERVAL -500 DAY, CURDATE() + INTERVAL 230 DAY, 88, 88, 3450, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(13, 7, 1, 'GF22E422', CURDATE() + INTERVAL -163 DAY, CURDATE() + INTERVAL 745 DAY, 41, 41, 3400, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 2)),
(14, 8, 4, 'PC25A158', CURDATE() + INTERVAL -399 DAY, CURDATE() + INTERVAL 331 DAY, 44, 44, 7550, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 7)),
(15, 8, 4, 'PC22E225', CURDATE() + INTERVAL -124 DAY, CURDATE() + INTERVAL 738 DAY, 46, 46, 7550, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 8)),
(16, 9, 1, 'GF24F898', CURDATE() + INTERVAL -243 DAY, CURDATE() + INTERVAL 487 DAY, 76, 76, 9400, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(17, 10, 2, 'MK22G423', CURDATE() + INTERVAL -210 DAY, CURDATE() + INTERVAL 520 DAY, 81, 81, 6200, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(18, 11, 3, 'LS26H536', CURDATE() + INTERVAL -742 DAY, CURDATE() + INTERVAL -12 DAY, 9, 9, 5950, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(19, 11, 3, 'LS22K483', CURDATE() + INTERVAL -350 DAY, CURDATE() + INTERVAL 380 DAY, 35, 35, 5900, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 6)),
(20, 12, 1, 'GF22L832', CURDATE() + INTERVAL -402 DAY, CURDATE() + INTERVAL 328 DAY, 64, 64, 4450, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(21, 12, 1, 'GF22E811', CURDATE() + INTERVAL -133 DAY, CURDATE() + INTERVAL 749 DAY, 52, 52, 4400, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 2)),
(22, 13, 2, 'MK22E886', CURDATE() + INTERVAL -706 DAY, CURDATE() + INTERVAL 24 DAY, 14, 14, 6900, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(23, 14, 1, 'GF26A838', CURDATE() + INTERVAL -231 DAY, CURDATE() + INTERVAL 499 DAY, 41, 41, 4350, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(24, 14, 1, 'GF23J225', CURDATE() + INTERVAL -103 DAY, CURDATE() + INTERVAL 627 DAY, 42, 42, 4050, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 2)),
(25, 15, 3, 'LS22G692', CURDATE() + INTERVAL -466 DAY, CURDATE() + INTERVAL 264 DAY, 73, 73, 3500, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(26, 15, 3, 'LS25G486', CURDATE() + INTERVAL -137 DAY, CURDATE() + INTERVAL 705 DAY, 49, 49, 3500, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 6)),
(27, 16, 2, 'MK26A777', CURDATE() + INTERVAL -315 DAY, CURDATE() + INTERVAL 415 DAY, 82, 82, 3950, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(28, 16, 2, 'MK26K668', CURDATE() + INTERVAL -158 DAY, CURDATE() + INTERVAL 572 DAY, 41, 41, 3850, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 4)),
(29, 17, 4, 'PC24C333', CURDATE() + INTERVAL -430 DAY, CURDATE() + INTERVAL 300 DAY, 7, 7, 8150, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 7)),
(30, 18, 2, 'BY23K707', CURDATE() + INTERVAL -389 DAY, CURDATE() + INTERVAL 341 DAY, 74, 74, 5000, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(31, 18, 2, 'BY23I138', CURDATE() + INTERVAL -123 DAY, CURDATE() + INTERVAL 607 DAY, 50, 50, 5250, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 4)),
(32, 19, 1, 'GF22K960', CURDATE() + INTERVAL -267 DAY, CURDATE() + INTERVAL 463 DAY, 56, 56, 3650, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(33, 19, 1, 'GF23H159', CURDATE() + INTERVAL -163 DAY, CURDATE() + INTERVAL 673 DAY, 50, 50, 3900, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 2)),
(34, 20, 3, 'LS25L468', CURDATE() + INTERVAL -270 DAY, CURDATE() + INTERVAL 460 DAY, 49, 49, 3200, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(35, 21, 1, 'GF24D483', CURDATE() + INTERVAL -411 DAY, CURDATE() + INTERVAL 319 DAY, 75, 75, 1750, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(36, 22, 2, 'MK26E292', CURDATE() + INTERVAL -296 DAY, CURDATE() + INTERVAL 434 DAY, 75, 75, 2150, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(37, 23, 3, 'LS25C596', CURDATE() + INTERVAL -655 DAY, CURDATE() + INTERVAL 75 DAY, 18, 18, 4600, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(38, 24, 1, 'GF22K276', CURDATE() + INTERVAL -349 DAY, CURDATE() + INTERVAL 381 DAY, 73, 73, 3400, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(39, 25, 4, 'PC24I848', CURDATE() + INTERVAL -320 DAY, CURDATE() + INTERVAL 410 DAY, 9, 9, 12250, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 7)),
(40, 26, 2, 'MK22A646', CURDATE() + INTERVAL -755 DAY, CURDATE() + INTERVAL -25 DAY, 6, 6, 6650, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(41, 26, 2, 'MK26E686', CURDATE() + INTERVAL -440 DAY, CURDATE() + INTERVAL 290 DAY, 22, 22, 6550, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 4)),
(42, 27, 3, 'LS25G651', CURDATE() + INTERVAL -718 DAY, CURDATE() + INTERVAL 12 DAY, 15, 15, 2150, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(43, 27, 3, 'LS26K777', CURDATE() + INTERVAL -130 DAY, CURDATE() + INTERVAL 600 DAY, 30, 30, 2050, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 6)),
(44, 28, 1, 'GF24I367', CURDATE() + INTERVAL -270 DAY, CURDATE() + INTERVAL 460 DAY, 46, 46, 900, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(45, 28, 1, 'GF26K906', CURDATE() + INTERVAL -118 DAY, CURDATE() + INTERVAL 727 DAY, 54, 54, 900, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 2)),
(46, 29, 1, 'GF24E654', CURDATE() + INTERVAL -380 DAY, CURDATE() + INTERVAL 350 DAY, 5, 5, 10800, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(47, 30, 2, 'MK23G293', CURDATE() + INTERVAL -675 DAY, CURDATE() + INTERVAL 55 DAY, 20, 20, 5350, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(48, 30, 2, 'MK22J763', CURDATE() + INTERVAL -250 DAY, CURDATE() + INTERVAL 480 DAY, 30, 30, 5150, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 4)),
(49, 31, 3, 'LS25F931', CURDATE() + INTERVAL -709 DAY, CURDATE() + INTERVAL 21 DAY, 12, 12, 5900, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(50, 31, 3, 'LS26C839', CURDATE() + INTERVAL -200 DAY, CURDATE() + INTERVAL 530 DAY, 25, 25, 5800, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 6)),
(51, 32, 4, 'PC22I783', CURDATE() + INTERVAL -439 DAY, CURDATE() + INTERVAL 291 DAY, 60, 60, 9700, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 7)),
(52, 32, 4, 'PC22F165', CURDATE() + INTERVAL -149 DAY, CURDATE() + INTERVAL 581 DAY, 31, 31, 9350, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 8)),
(53, 33, 3, 'LS23I257', CURDATE() + INTERVAL -770 DAY, CURDATE() + INTERVAL -40 DAY, 11, 11, 4800, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(54, 33, 3, 'LS23C208', CURDATE() + INTERVAL -370 DAY, CURDATE() + INTERVAL 360 DAY, 20, 20, 4950, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 6)),
(55, 34, 1, 'GF22G368', CURDATE() + INTERVAL -282 DAY, CURDATE() + INTERVAL 448 DAY, 46, 46, 2200, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(56, 35, 1, 'GF26I352', CURDATE() + INTERVAL -470 DAY, CURDATE() + INTERVAL 260 DAY, 62, 62, 3350, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(57, 35, 1, 'GF25J453', CURDATE() + INTERVAL -148 DAY, CURDATE() + INTERVAL 667 DAY, 37, 37, 3200, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 2)),
(58, 36, 2, 'MK22H896', CURDATE() + INTERVAL -646 DAY, CURDATE() + INTERVAL 84 DAY, 16, 16, 4100, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(59, 37, 1, 'GF24F841', CURDATE() + INTERVAL -415 DAY, CURDATE() + INTERVAL 315 DAY, 50, 50, 1500, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 1)),
(60, 37, 1, 'GF25G421', CURDATE() + INTERVAL -118 DAY, CURDATE() + INTERVAL 669 DAY, 65, 65, 1450, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 2)),
(61, 38, 3, 'LS24F519', CURDATE() + INTERVAL -293 DAY, CURDATE() + INTERVAL 437 DAY, 54, 54, 4050, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 5)),
(62, 39, 4, 'LF23G374', CURDATE() + INTERVAL -228 DAY, CURDATE() + INTERVAL 502 DAY, 64, 64, 6400, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 7)),
(63, 39, 4, 'LF22F372', CURDATE() + INTERVAL -169 DAY, CURDATE() + INTERVAL 653 DAY, 66, 66, 6600, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 8)),
(64, 40, 2, 'MK25E248', CURDATE() + INTERVAL -738 DAY, CURDATE() + INTERVAL -8 DAY, 4, 4, 7200, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 3)),
(65, 41, 5, 'JG22E400', CURDATE() + INTERVAL -393 DAY, CURDATE() + INTERVAL 337 DAY, 54, 54, 3500, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 9)),
(66, 41, 5, 'JG25G122', CURDATE() + INTERVAL -154 DAY, CURDATE() + INTERVAL 576 DAY, 65, 65, 3500, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 10)),
(67, 42, 5, 'IO26I314', CURDATE() + INTERVAL -362 DAY, CURDATE() + INTERVAL 368 DAY, 83, 83, 1800, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 9)),
(68, 42, 5, 'IO24A509', CURDATE() + INTERVAL -166 DAY, CURDATE() + INTERVAL 564 DAY, 61, 61, 1800, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 10)),
(69, 43, 5, 'IO24C442', CURDATE() + INTERVAL -525 DAY, CURDATE() + INTERVAL 205 DAY, 57, 57, 2800, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 9)),
(70, 44, 5, 'CP26G952', CURDATE() + INTERVAL -685 DAY, CURDATE() + INTERVAL 45 DAY, 18, 18, 3250, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 9)),
(71, 44, 5, 'CP25H446', CURDATE() + INTERVAL -141 DAY, CURDATE() + INTERVAL 700 DAY, 30, 30, 3050, (SELECT fecha_entrada FROM entradas WHERE id_entrada = 10));

INSERT INTO detalle_entrada (id_entrada, id_lote, cantidad, costo_unitario, subtotal) VALUES
(1, 1, 57, 2750, 156750),
(2, 2, 35, 2900, 101500),
(3, 3, 25, 4100, 102500),
(4, 4, 40, 4050, 162000),
(5, 5, 90, 3050, 274500),
(6, 6, 43, 3050, 131150),
(1, 7, 41, 2550, 104550),
(2, 8, 52, 2550, 132600),
(3, 9, 88, 5500, 484000),
(5, 10, 30, 3250, 97500),
(6, 11, 40, 3100, 124000),
(1, 12, 88, 3450, 303600),
(2, 13, 41, 3400, 139400),
(7, 14, 44, 7550, 332200),
(8, 15, 46, 7550, 347300),
(1, 16, 76, 9400, 714400),
(3, 17, 81, 6200, 502200),
(5, 18, 9, 5950, 53550),
(6, 19, 35, 5900, 206500),
(1, 20, 64, 4450, 284800),
(2, 21, 52, 4400, 228800),
(3, 22, 14, 6900, 96600),
(1, 23, 41, 4350, 178350),
(2, 24, 42, 4050, 170100),
(5, 25, 73, 3500, 255500),
(6, 26, 49, 3500, 171500),
(3, 27, 82, 3950, 323900),
(4, 28, 41, 3850, 157850),
(7, 29, 7, 8150, 57050),
(3, 30, 74, 5000, 370000),
(4, 31, 50, 5250, 262500),
(1, 32, 56, 3650, 204400),
(2, 33, 50, 3900, 195000),
(5, 34, 49, 3200, 156800),
(1, 35, 75, 1750, 131250),
(3, 36, 75, 2150, 161250),
(5, 37, 18, 4600, 82800),
(1, 38, 73, 3400, 248200),
(7, 39, 9, 12250, 110250),
(3, 40, 6, 6650, 39900),
(4, 41, 22, 6550, 144100),
(5, 42, 15, 2150, 32250),
(6, 43, 30, 2050, 61500),
(1, 44, 46, 900, 41400),
(2, 45, 54, 900, 48600),
(1, 46, 5, 10800, 54000),
(3, 47, 20, 5350, 107000),
(4, 48, 30, 5150, 154500),
(5, 49, 12, 5900, 70800),
(6, 50, 25, 5800, 145000),
(7, 51, 60, 9700, 582000),
(8, 52, 31, 9350, 289850),
(5, 53, 11, 4800, 52800),
(6, 54, 20, 4950, 99000),
(1, 55, 46, 2200, 101200),
(1, 56, 62, 3350, 207700),
(2, 57, 37, 3200, 118400),
(3, 58, 16, 4100, 65600),
(1, 59, 50, 1500, 75000),
(2, 60, 65, 1450, 94250),
(5, 61, 54, 4050, 218700),
(7, 62, 64, 6400, 409600),
(8, 63, 66, 6600, 435600),
(3, 64, 4, 7200, 28800),
(9, 65, 54, 3500, 189000),
(10, 66, 65, 3500, 227500),
(9, 67, 83, 1800, 149400),
(10, 68, 61, 1800, 109800),
(9, 69, 57, 2800, 159600),
(9, 70, 18, 3250, 58500),
(10, 71, 30, 3050, 91500);

UPDATE entradas e
   SET total = (SELECT COALESCE(SUM(d.subtotal), 0) FROM detalle_entrada d WHERE d.id_entrada = e.id_entrada);

-- Kárdex: cada lote recibido genera su movimiento de ENTRADA
INSERT INTO movimientos_inventario (id_lote, id_medicamento, tipo, cantidad, saldo_lote, motivo, id_entrada, id_usuario, fecha)
SELECT l.id_lote, l.id_medicamento, 'ENTRADA', d.cantidad, d.cantidad,
       CONCAT('Entrada factura ', e.numero_factura), e.id_entrada, e.id_usuario, e.fecha_entrada
  FROM detalle_entrada d
  JOIN lotes l    ON l.id_lote = d.id_lote
  JOIN entradas e ON e.id_entrada = d.id_entrada
 ORDER BY e.fecha_entrada, l.id_lote;
