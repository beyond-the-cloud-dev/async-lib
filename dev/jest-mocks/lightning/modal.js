import { LightningElement, api } from 'lwc';

export default class LightningModal extends LightningElement {
    @api label;
    @api size;
    static open = jest.fn(() => Promise.resolve());
    close() {}
}
