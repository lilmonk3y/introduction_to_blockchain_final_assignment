// SPDX-License-Identifier: MIT
pragma solidity >=0.5.9;

import "./Equation.sol";

contract FunctionMinimization {
    using Equation for Equation.Node[];

    struct FunctionEntry {
        Equation.Node[] equation;
        uint256 reward;
        address payable publisher;
        bool rewardPaid; 
    }


    FunctionEntry[] public functions;

    function publishFunction(uint256[] memory expressions) public payable {
        // Añadir una nueva entrada vacía al array 'functions'
        functions.push();
        uint256 functionIndex = functions.length - 1;

        // Configurar la nueva entrada
        FunctionEntry storage newEntry = functions[functionIndex];
        newEntry.reward = msg.value;  // Utiliza el valor enviado como recompensa
        newEntry.publisher = payable(msg.sender);

        // Inicializar la ecuación con el array de expresiones proporcionado
        Equation.init(newEntry.equation, expressions);
    }


    function submitMinimum(uint256 functionId, uint256 minimum) external payable{
        require(functionId < functions.length, "Invalid function ID");
        FunctionEntry storage funcEntry = functions[functionId];

        // Verificar que la recompensa aún no haya sido pagada
        require(!funcEntry.rewardPaid, "Reward already paid");

        // Evalúa la función en el valor mínimo propuesto
        uint256 evaluatedValue = funcEntry.equation.calculate(minimum);
        require(evaluatedValue == 0, "Not a valid minimum");

        // Verificar que hay suficiente balance en el contrato para pagar la recompensa
        require(address(this).balance >= funcEntry.reward, "Insufficient balance in contract");

        // Transfiere la recompensa al remitente y marca como pagada

        payable(msg.sender).transfer(funcEntry.reward);

        funcEntry.rewardPaid = true; // Marcar la recompensa como pagada
    }

  // The receive function is called when Ether is sent to the contract with no calldata
    receive() external payable {
        // Logic to handle plain Ether transfers, if any
    }

    // The fallback function is called when a function that doesn't exist is called or when Ether is sent with calldata
    fallback() external payable {
        // Logic to handle calls to non-existent functions, if any
    }
}
