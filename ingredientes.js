// Base de ingredientes para sugerir al cargar recetas (español rioplatense).
// Agrupados por categoría solo para mantenerla ordenada; la app usa la lista completa.
window.INGREDIENTES_BASE = [
  // Verduras y hortalizas
  'Acelga', 'Achicoria', 'Ají morrón rojo', 'Ají morrón verde', 'Ají morrón amarillo', 'Ajo', 'Ajo negro', 'Alcaparras',
  'Alcaucil', 'Apio', 'Apio nabo', 'Arvejas', 'Arvejas congeladas', 'Batata', 'Berenjena', 'Berro', 'Brócoli', 'Brotes de soja',
  'Calabacín', 'Calabaza', 'Cebolla', 'Cebolla de verdeo', 'Cebolla morada', 'Cebolla blanca', 'Cebollín', 'Chaucha', 'Choclo',
  'Choclo en grano', 'Coliflor', 'Endibia', 'Escarola', 'Espárragos', 'Espinaca', 'Hinojo', 'Hongos de pino', 'Hongos portobello',
  'Champiñones', 'Gírgolas', 'Shiitake', 'Jengibre', 'Kale', 'Lechuga', 'Lechuga criolla', 'Lechuga mantecosa', 'Lechuga morada',
  'Lechuga romana', 'Mandioca', 'Nabo', 'Palta', 'Papa', 'Papa andina', 'Pepino', 'Puerro', 'Rabanito', 'Radicheta', 'Remolacha',
  'Repollo', 'Repollo colorado', 'Repollitos de Bruselas', 'Rúcula', 'Tomate', 'Tomate perita', 'Tomate cherry', 'Tomate redondo',
  'Tomates secos', 'Topinambur', 'Zanahoria', 'Zapallito', 'Zapallo', 'Zapallo anco', 'Zapallo cabutia', 'Zucchini', 'Ají picante',
  'Jalapeño', 'Chile', 'Pimiento de padrón', 'Aceitunas verdes', 'Aceitunas negras', 'Corazones de palmito', 'Germen de alfalfa',
  'Pak choi', 'Chirivía', 'Okra', 'Cardo', 'Ajo porro',

  // Frutas
  'Ananá', 'Arándanos', 'Banana', 'Cereza', 'Ciruela', 'Ciruelas pasas', 'Coco', 'Coco rallado', 'Damasco', 'Damascos secos',
  'Durazno', 'Duraznos en almíbar', 'Frambuesa', 'Frutilla', 'Granada', 'Higo', 'Higos secos', 'Kiwi', 'Lima', 'Limón', 'Mandarina',
  'Mango', 'Manzana', 'Manzana verde', 'Maracuyá', 'Melón', 'Membrillo', 'Mora', 'Naranja', 'Pasas de uva', 'Pera', 'Pomelo',
  'Sandía', 'Uva', 'Dátiles', 'Arándanos secos', 'Cáscara de limón', 'Cáscara de naranja', 'Jugo de limón', 'Jugo de naranja',
  'Ralladura de limón', 'Ralladura de naranja', 'Fruta abrillantada', 'Cerezas al marrasquino', 'Quinoto', 'Kaki', 'Papaya',
  'Lichi', 'Pitaya',

  // Carnes vacunas
  'Asado de tira', 'Bife de chorizo', 'Bife ancho', 'Bife angosto', 'Bola de lomo', 'Carne picada', 'Carne picada especial',
  'Carne para guiso', 'Colita de cuadril', 'Cuadrada', 'Cuadril', 'Entraña', 'Falda', 'Lomo', 'Matambre', 'Nalga', 'Osobuco',
  'Paleta', 'Peceto', 'Roast beef', 'Tapa de asado', 'Tapa de nalga', 'Tortuguita', 'Vacío', 'Palomita', 'Marucha', 'Aguja',
  'Hígado', 'Lengua', 'Mondongo', 'Riñón', 'Molleja', 'Chinchulines', 'Morcilla', 'Chorizo', 'Chorizo colorado', 'Salchicha parrillera',

  // Cerdo, cordero y otras carnes
  'Bondiola', 'Carré de cerdo', 'Costillas de cerdo', 'Matambre de cerdo', 'Pechito de cerdo', 'Solomillo de cerdo', 'Carne picada de cerdo',
  'Panceta', 'Panceta ahumada', 'Tocino', 'Jamón cocido', 'Jamón crudo', 'Lomito ahumado', 'Salame', 'Salamín', 'Mortadela',
  'Leberwurst', 'Salchichas', 'Cordero', 'Pierna de cordero', 'Chivito', 'Conejo', 'Pato', 'Ciervo', 'Jabalí',

  // Aves
  'Pollo entero', 'Pechuga de pollo', 'Suprema de pollo', 'Muslo de pollo', 'Pata y muslo', 'Alitas de pollo', 'Carne picada de pollo',
  'Pavo', 'Pechuga de pavo', 'Hígados de pollo', 'Codorniz',

  // Pescados y mariscos
  'Atún', 'Atún en lata', 'Abadejo', 'Bacalao', 'Besugo', 'Brótola', 'Caballa', 'Corvina', 'Lenguado', 'Merluza', 'Mero', 'Pejerrey',
  'Salmón', 'Salmón ahumado', 'Sardinas', 'Sardinas en lata', 'Trucha', 'Anchoas', 'Surimi', 'Calamar', 'Rabas', 'Langostinos',
  'Camarones', 'Mejillones', 'Almejas', 'Vieiras', 'Pulpo', 'Kanikama', 'Caviar', 'Dorado', 'Pacú', 'Boga', 'Tilapia',

  // Huevos y lácteos
  'Huevo', 'Clara de huevo', 'Yema de huevo', 'Huevo de codorniz', 'Leche', 'Leche descremada', 'Leche en polvo', 'Leche condensada',
  'Leche evaporada', 'Crema de leche', 'Crema doble', 'Crema ácida', 'Manteca', 'Manteca sin sal', 'Ghee', 'Yogur natural',
  'Yogur griego', 'Dulce de leche', 'Dulce de leche repostero', 'Queso crema', 'Queso blanco', 'Ricota', 'Mascarpone', 'Mozzarella',
  'Queso cremoso', 'Queso de máquina', 'Queso tybo', 'Queso dambo', 'Queso fontina', 'Queso gruyère', 'Queso parmesano',
  'Queso reggianito', 'Queso sardo', 'Queso provolone', 'Provoleta', 'Queso roquefort', 'Queso azul', 'Queso brie', 'Queso camembert',
  'Queso cheddar', 'Queso de cabra', 'Queso feta', 'Queso pategrás', 'Queso holanda', 'Queso rallado', 'Queso por salut',
  'Queso mar del plata', 'Queso emmental', 'Burrata', 'Bocconcini', 'Suero de leche', 'Kéfir', 'Crema chantilly',

  // Harinas, cereales y masas
  'Harina 0000', 'Harina 000', 'Harina leudante', 'Harina integral', 'Harina de maíz', 'Harina de arroz', 'Harina de garbanzo',
  'Harina de almendras', 'Harina de coco', 'Harina de mandioca', 'Fécula de maíz', 'Almidón de maíz', 'Fécula de mandioca',
  'Polenta', 'Sémola', 'Avena', 'Avena instantánea', 'Salvado de avena', 'Salvado de trigo', 'Germen de trigo', 'Trigo burgol',
  'Cuscús', 'Quinoa', 'Amaranto', 'Mijo', 'Cebada perlada', 'Trigo candeal', 'Maíz pisado', 'Maíz blanco', 'Arroz', 'Arroz largo fino',
  'Arroz doble carolina', 'Arroz yamaní', 'Arroz integral', 'Arroz arbóreo', 'Arroz carnaroli', 'Arroz basmati', 'Arroz jazmín',
  'Arroz para sushi', 'Pan rallado', 'Rebozador', 'Panko', 'Pan', 'Pan francés', 'Pan lactal', 'Pan integral', 'Pan de campo',
  'Pan árabe', 'Pan de hamburguesa', 'Pan de pancho', 'Baguette', 'Ciabatta', 'Grisines', 'Galletitas de agua', 'Galletitas dulces',
  'Galletitas de chocolate', 'Vainillas', 'Bizcochuelo', 'Tapas de empanadas', 'Tapas de empanadas de hojaldre', 'Tapas de tarta',
  'Masa de hojaldre', 'Masa filo', 'Masa de pizza', 'Prepizza', 'Tortillas de trigo', 'Tortillas de maíz', 'Discos de pascualina',
  'Obleas', 'Copos de maíz', 'Granola', 'Levadura fresca', 'Levadura seca', 'Polvo de hornear', 'Bicarbonato de sodio',

  // Pastas
  'Fideos spaghetti', 'Fideos tallarines', 'Fideos mostachol', 'Fideos tirabuzón', 'Fideos moñito', 'Fideos codito',
  'Fideos dedalitos', 'Fideos cabello de ángel', 'Fideos de arroz', 'Fideos de huevo', 'Fideos integrales', 'Penne', 'Fusilli',
  'Rigatoni', 'Linguine', 'Fettuccine', 'Pappardelle', 'Ravioles', 'Sorrentinos', 'Agnolotis', 'Capelettis', 'Ñoquis', 'Lasaña',
  'Canelones', 'Fideos soba', 'Fideos udon', 'Fideos ramen', 'Masa para wonton',

  // Legumbres, frutos secos y semillas
  'Lentejas', 'Lentejas rojas', 'Garbanzos', 'Porotos', 'Porotos negros', 'Porotos colorados', 'Porotos alubia', 'Porotos pallares',
  'Porotos aduki', 'Soja', 'Arvejas secas', 'Habas', 'Tofu', 'Tempeh', 'Seitán', 'Proteína de soja texturizada', 'Edamame',
  'Almendras', 'Avellanas', 'Castañas de cajú', 'Castañas', 'Maní', 'Maní tostado', 'Nueces', 'Nueces pecán', 'Pistachos',
  'Piñones', 'Macadamias', 'Semillas de chía', 'Semillas de lino', 'Semillas de girasol', 'Semillas de zapallo', 'Semillas de sésamo',
  'Sésamo negro', 'Semillas de amapola', 'Pasta de maní', 'Tahini', 'Mix de frutos secos', 'Cacao en polvo', 'Coco en escamas',

  // Aceites, vinagres y grasas
  'Aceite', 'Aceite de girasol', 'Aceite de oliva', 'Aceite de oliva extra virgen', 'Aceite de maíz', 'Aceite de coco',
  'Aceite de sésamo', 'Aceite en aerosol', 'Grasa vacuna', 'Grasa de cerdo', 'Margarina', 'Vinagre', 'Vinagre de alcohol',
  'Vinagre de vino', 'Vinagre de manzana', 'Aceto balsámico', 'Vinagre de arroz', 'Aceto balsámico reducido',

  // Condimentos, especias y hierbas
  'Sal', 'Sal gruesa', 'Sal fina', 'Sal marina', 'Sal parrillera', 'Pimienta', 'Pimienta negra', 'Pimienta blanca', 'Pimienta rosa',
  'Pimienta en grano', 'Ají molido', 'Pimentón', 'Pimentón dulce', 'Pimentón ahumado', 'Comino', 'Orégano', 'Laurel', 'Tomillo',
  'Romero', 'Albahaca', 'Perejil', 'Cilantro', 'Menta', 'Hierbabuena', 'Eneldo', 'Estragón', 'Salvia', 'Ciboulette', 'Mejorana',
  'Nuez moscada', 'Canela', 'Canela en rama', 'Clavo de olor', 'Anís estrellado', 'Cardamomo', 'Cúrcuma', 'Curry', 'Garam masala',
  'Jengibre en polvo', 'Ajo en polvo', 'Cebolla en polvo', 'Provenzal', 'Chimichurri', 'Condimento para pizza', 'Condimento para arroz',
  'Hierbas de Provenza', 'Merkén', 'Azafrán', 'Vainilla', 'Esencia de vainilla', 'Chaucha de vainilla', 'Extracto de almendras',
  'Agua de azahar', 'Semillas de hinojo', 'Semillas de mostaza', 'Fenogreco', 'Zaatar', 'Sumac', 'Ras el hanout', 'Pimienta de cayena',
  'Paprika', 'Caldo en cubos', 'Caldo de verdura', 'Caldo de carne', 'Caldo de pollo', 'Caldo de pescado', 'Glutamato monosódico',

  // Salsas y aderezos
  'Mayonesa', 'Mostaza', 'Mostaza de Dijon', 'Mostaza en grano', 'Ketchup', 'Salsa golf', 'Salsa de soja', 'Salsa teriyaki',
  'Salsa inglesa', 'Salsa barbacoa', 'Salsa picante', 'Tabasco', 'Sriracha', 'Salsa de tomate', 'Puré de tomate', 'Tomate triturado',
  'Tomate en lata', 'Extracto de tomate', 'Pesto', 'Salsa blanca', 'Salsa bechamel', 'Salsa criolla', 'Salsa de ostras',
  'Salsa de pescado', 'Pasta de curry', 'Miso', 'Gochujang', 'Salsa tártara', 'Alioli', 'Hummus', 'Guacamole', 'Mermelada',
  'Mermelada de frutilla', 'Mermelada de durazno', 'Mermelada de naranja', 'Dulce de membrillo', 'Dulce de batata', 'Miel',
  'Jarabe de arce', 'Melaza', 'Wasabi', 'Jengibre encurtido', 'Pepinillos', 'Chucrut', 'Mostaza a la antigua',

  // Azúcares y repostería
  'Azúcar', 'Azúcar impalpable', 'Azúcar mascabo', 'Azúcar negra', 'Azúcar rubia', 'Azúcar glas', 'Edulcorante', 'Stevia',
  'Glucosa', 'Chocolate', 'Chocolate semiamargo', 'Chocolate con leche', 'Chocolate blanco', 'Chocolate para taza', 'Chips de chocolate',
  'Cobertura de chocolate', 'Cacao amargo', 'Gelatina sin sabor', 'Gelatina de sabor', 'Agar agar', 'Grana de colores', 'Mazapán',
  'Pasta de azúcar', 'Fondant', 'Merengue', 'Crema pastelera', 'Colorante alimentario', 'Cremor tártaro', 'Caramelo', 'Praliné',
  'Pasta de avellanas', 'Turrón', 'Bizcochos de grasa', 'Alfajores', 'Polvo para flan', 'Polvo para budín',

  // Bebidas y otros líquidos
  'Agua', 'Agua con gas', 'Soda', 'Vino blanco', 'Vino tinto', 'Vino rosado', 'Vino dulce', 'Oporto', 'Jerez', 'Cerveza',
  'Cerveza negra', 'Sidra', 'Champagne', 'Ron', 'Coñac', 'Brandy', 'Whisky', 'Vodka', 'Licor de café', 'Licor de naranja', 'Grappa',
  'Fernet', 'Café', 'Café instantáneo', 'Té', 'Té verde', 'Mate cocido', 'Yerba mate', 'Leche de coco', 'Leche de almendras',
  'Leche de avena', 'Leche de soja', 'Crema de coco', 'Jugo de manzana', 'Jugo de tomate', 'Gaseosa cola', 'Agua tónica',

  // Comida preparada y conservas
  'Choclo cremoso', 'Arvejas en lata', 'Garbanzos en lata', 'Lentejas en lata', 'Porotos en lata', 'Champiñones en lata',
  'Ananá en almíbar', 'Peras en almíbar', 'Palmitos', 'Morrones asados', 'Berenjenas en escabeche', 'Escabeche', 'Puré de papas instantáneo',
  'Medallones de carne', 'Hamburguesas', 'Milanesas', 'Nuggets', 'Papas fritas congeladas', 'Verduras congeladas', 'Sopa instantánea',
  'Fideos instantáneos', 'Picadillo de carne', 'Paté', 'Jamón serrano', 'Bresaola', 'Pastrón', 'Chorizo español', 'Chistorra',
  'Sobrasada', 'Salchichón', 'Queso untable', 'Crutones', 'Nachos', 'Papas chips', 'Pochoclo', 'Algas nori', 'Algas wakame',
  'Mirin', 'Sake', 'Kimchi', 'Leche de cabra', 'Hojas de parra', 'Hojas de banana', 'Chalas de choclo',   'Harina de algarroba', 'Arrope', 'Quesillo', 'Charqui', 'Mote', 'Tamales', 'Humita',
];
