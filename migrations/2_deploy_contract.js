const Tesseract = artifacts.require("TesseractV1");
const args = process.argv;

module.exports = function (deployer) {
	if (args.length < 8) {
		throw new Error("Not enough arguments");
	}

	deployer.deploy(Tesseract, args[5], args[6], parseInt(args[7]));
};
